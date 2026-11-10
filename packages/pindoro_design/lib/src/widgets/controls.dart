import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'pindoro_button.dart';
import 'surfaces.dart';
import 'tappable.dart';

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
/// raised on a 2 dp lip. Announced as selectable buttons; tapping the
/// selected one changes nothing.
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
    // The track's top and bottom padding sit inside each segment's target:
    // 52 dp tall to the finger, 44 dp to the eye.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s1),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
      ),
      child: Row(
        children: [
          for (final (i, MapEntry(key: value, value: label)) in entries.indexed)
            Expanded(
              child: _Segment(
                label: label,
                semanticLabel: '$label, ${i + 1} / ${entries.length}',
                selected: value == selected,
                onTap: () {
                  if (value != selected) onChanged(value);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Tappable(
      selected: selected,
      label: semanticLabel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s1),
        child: AnimatedContainer(
          duration: PindoroMotion.durationQuick,
          curve: PindoroMotion.easeStandard,
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s2),
          decoration: BoxDecoration(
            color: selected ? c.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(PindoroRadius.md),
            border: selected
                ? Border(
                    bottom: BorderSide(
                      color: c.lineBase,
                      width: PindoroElevation.e1,
                    ),
                  )
                : null,
          ),
          // Long translated labels shrink instead of wrapping.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: PindoroType.labelLg.copyWith(
                color: selected ? c.primaryText : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three lane dashes driving left to right: the system's loading indicator.
/// Stands still when reduce motion is on. Decorative: the text beside it says
/// what is loading.
class LaneLoader extends StatefulWidget {
  const LaneLoader({super.key});

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
    final color = PindoroTheme.of(context).colors.primaryBase;
    return ExcludeSemantics(
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
    this.size = PindoroSize.tapMin,
  });

  final PindoroGlyph glyph;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Outer size, border and lip included: 48, or 56 beside a full button.
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Tappable(
      label: semanticLabel,
      onTap: onPressed,
      child: LipBox(
        radius: PindoroRadius.md,
        border: c.buttonSecondaryBorder,
        child: SizedBox(
          width: size - 2 * PindoroStroke.base,
          height: size - PindoroElevation.e1 - 2 * PindoroStroke.base,
          child: Center(
            child: PindoroIcon(glyph, color: c.buttonSecondaryText),
          ),
        ),
      ),
    );
  }
}

/// A centred decision: title, body, the safe action first (primary) and the
/// leaving action under it (tertiary). Pops `true` when the leaving action is
/// chosen; back and the scrim keep the safe action.
class PindoroDialog extends StatelessWidget {
  const PindoroDialog({
    super.key,
    required this.title,
    required this.body,
    required this.primary,
    required this.secondary,
  });

  final String title;
  final String body;
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(PindoroSpace.s6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(PindoroSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: PindoroType.headlineSm.copyWith(color: c.textPrimary),
                ),
              ),
              Text(
                body,
                style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: PindoroSpace.s2),
              PindoroButton(
                label: primary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              PindoroButton(
                label: secondary,
                variant: PindoroButtonVariant.tertiary,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
