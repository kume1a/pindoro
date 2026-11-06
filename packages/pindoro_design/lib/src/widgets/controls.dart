import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'surfaces.dart';

/// A 56 × 32 switch; put it in a [ListRow] so the whole row is the target.
class PindoroToggle extends StatelessWidget {
  const PindoroToggle({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double _width = 56;
  static const double _height = 32;
  static const double _thumb = 24;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final enabled = onChanged != null;
    final track = !enabled
        ? c.buttonDisabledBg
        : value
        ? c.toggleOn
        : c.toggleOff;
    return GestureDetector(
      onTap: enabled ? () => onChanged!(!value) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: AnimatedContainer(
          duration: PindoroMotion.durationQuick,
          curve: PindoroMotion.easeStandard,
          width: _width,
          height: _height,
          padding: const EdgeInsets.all((_height - _thumb) / 2),
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(PindoroRadius.full),
          ),
          child: AnimatedAlign(
            duration: PindoroMotion.durationQuick,
            curve: PindoroMotion.easeOvershoot,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: _thumb,
              height: _thumb,
              decoration: BoxDecoration(
                color: c.toggleThumb,
                shape: BoxShape.circle,
                border: Border(
                  bottom: BorderSide(
                    color: value ? c.primaryLip : c.lineStrong,
                    width: PindoroElevation.e1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two to four exclusive options in a sunken track; the selected segment is
/// raised on a 2 dp lip. Announced as a tab list.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final entries = segments.entries.toList();
    return Container(
      padding: const EdgeInsets.all(PindoroSpace.s1),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
      ),
      child: Row(
        children: [
          for (final (i, MapEntry(key: value, value: label)) in entries.indexed)
            Expanded(
              child: Semantics(
                selected: value == selected,
                button: true,
                label: '$label, ${i + 1} / ${entries.length}',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onChanged(value),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: PindoroMotion.durationQuick,
                      curve: PindoroMotion.easeStandard,
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: PindoroSpace.s2,
                      ),
                      decoration: BoxDecoration(
                        color: value == selected
                            ? c.surfaceRaised
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(PindoroRadius.md),
                        border: value == selected
                            ? Border(
                                bottom: BorderSide(
                                  color: c.lineBase,
                                  width: PindoroElevation.e1,
                                ),
                              )
                            : null,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: PindoroType.labelLg.copyWith(
                          color: value == selected
                              ? c.primaryText
                              : c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Three lane dashes driving left to right: the system's loading indicator.
/// Stands still when reduce motion is on.
class LaneLoader extends StatefulWidget {
  const LaneLoader({super.key, this.color});

  /// Defaults to `color.primary.base`.
  final Color? color;

  @override
  State<LaneLoader> createState() => _LaneLoaderState();
}

class _LaneLoaderState extends State<LaneLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drive = AnimationController(
    vsync: this,
    duration: PindoroMotion.durationSlow * 2,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drive.stop();
    } else if (!_drive.isAnimating) {
      _drive.repeat();
    }
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? PindoroTheme.of(context).colors.primaryBase;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: SizedBox(
        width: 48,
        height: 8,
        child: AnimatedBuilder(
          animation: _drive,
          builder: (_, _) => CustomPaint(
            painter: _LanePainter(color: color, progress: _drive.value),
          ),
        ),
      ),
    );
  }
}

class _LanePainter extends CustomPainter {
  _LanePainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height / 2
      ..strokeCap = StrokeCap.round;
    final period = size.width / 3;
    final dash = period / 2;
    canvas.clipRect(Offset.zero & size);
    for (var i = -1; i < 3; i++) {
      final x = (i + progress) * period;
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(x + dash, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.progress != progress || old.color != color;
}

/// A 48 dp icon-only button in secondary colours; always labelled.
class PindoroIconButton extends StatelessWidget {
  const PindoroIconButton({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    required this.onPressed,
  });

  final PindoroGlyph glyph;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: MouseRegion(
          cursor: onPressed == null
              ? SystemMouseCursors.forbidden
              : SystemMouseCursors.click,
          child: LipBox(
            radius: PindoroRadius.md,
            border: c.buttonSecondaryBorder,
            child: SizedBox.square(
              dimension: PindoroSize.tapMin - PindoroElevation.e1,
              child: Center(
                child: PindoroIcon(glyph, color: c.buttonSecondaryText),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
