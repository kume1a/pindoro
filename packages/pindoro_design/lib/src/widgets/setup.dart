import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'controls.dart';
import 'graphics.dart';
import 'surfaces.dart';

/// A 56 dp search field on a 2 dp lip; the border and lip turn cobalt while
/// focused, and a clear button shows once there is text.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.clearLabel,
    this.onChanged,
    this.loading = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final String clearLabel;
  final ValueChanged<String>? onChanged;
  final bool loading;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final edge = _focus.hasFocus ? c.inputBorderFocus : c.inputBorder;
    return LipBox(
      face: c.inputBg,
      lip: edge,
      border: edge,
      radius: PindoroRadius.lg,
      child: SizedBox(
        height: PindoroSize.buttonLg - PindoroElevation.e1,
        child: Row(
          children: [
            const SizedBox(width: PindoroSpace.s4),
            PindoroIcon(PindoroGlyph.search, color: c.inputIcon),
            const SizedBox(width: PindoroSpace.s2),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                onChanged: widget.onChanged,
                textInputAction: TextInputAction.search,
                cursorColor: c.primaryBase,
                style: PindoroType.bodyLg.copyWith(color: c.inputText),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: widget.placeholder,
                  hintStyle: PindoroType.bodyLg.copyWith(
                    color: c.inputPlaceholder,
                  ),
                ),
              ),
            ),
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: PindoroSpace.s3),
                child: LaneLoader(),
              )
            else if (widget.controller.text.isNotEmpty)
              Semantics(
                button: true,
                label: widget.clearLabel,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    widget.controller.clear();
                    widget.onChanged?.call('');
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SizedBox.square(
                      dimension: PindoroSize.tapMin,
                      child: Center(
                        child: PindoroIcon(
                          PindoroGlyph.close,
                          size: PindoroSize.iconSm,
                          color: c.inputIcon,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Home's top-left control: pin, city name, chevron.
class CitySwitcher extends StatelessWidget {
  const CitySwitcher({
    super.key,
    required this.city,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String city;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(PindoroRadius.md),
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceSunken,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            height: PindoroSize.tapMin,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: PindoroSpace.s1,
                children: [
                  PindoroIcon(PindoroGlyph.pin, size: 22, color: c.primaryText),
                  Flexible(
                    child: Text(
                      city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PindoroType.titleMd.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  PindoroIcon(
                    PindoroGlyph.chevronDown,
                    size: 18,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped toggle (districts): 40 dp face inside a 48 dp target; a
/// selected chip is cobalt-soft with a check.
class PindoroChip extends StatelessWidget {
  const PindoroChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final ink = selected ? c.chipSelectedText : c.chipText;
    return Semantics(
      checked: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s1),
            child: LipBox(
              face: selected ? c.chipSelectedBg : c.chipBg,
              lip: selected ? c.chipSelectedBorder : c.chipBorder,
              border: selected ? c.chipSelectedBorder : c.chipBorder,
              radius: PindoroRadius.full,
              padding: const EdgeInsets.symmetric(
                horizontal: PindoroSpace.s3,
                vertical: PindoroSpace.s2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: PindoroSpace.s1,
                children: [
                  if (selected)
                    PindoroIcon(
                      PindoroGlyph.check,
                      size: PindoroSize.iconSm,
                      color: ink,
                    ),
                  Text(label, style: PindoroType.labelLg.copyWith(color: ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable difficulty: road art (more and thinner roads per level), the
/// name, a four-bar gauge and the description. One of four in a radio group.
class DifficultyCard extends StatelessWidget {
  const DifficultyCard({
    super.key,
    required this.difficulty,
    required this.name,
    required this.description,
    required this.selected,
    required this.onPressed,
  });

  final Difficulty difficulty;
  final String name;
  final String description;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final level = difficulty.index + 1;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$name, $description, $level / 4',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: PindoroMotion.durationQuick,
            child: LipBox(
              face: selected ? c.primarySoft : c.surfaceRaised,
              lip: selected ? c.primaryBase : c.lineBase,
              border: selected ? c.primaryBase : c.lineBase,
              lipHeight: PindoroElevation.e2,
              child: Padding(
                padding: const EdgeInsets.all(PindoroSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: PindoroSpace.s2,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(PindoroRadius.md),
                      child: SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _RoadArt(colors: c, level: level),
                        ),
                      ),
                    ),
                    Text(
                      name,
                      style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                    ),
                    Row(
                      spacing: 3,
                      children: [
                        for (var i = 1; i <= 4; i++)
                          Container(
                            width: 14,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i <= level ? c.primaryText : c.xpTrack,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      description,
                      style: PindoroType.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A grid of streets on the basemap; [level] of them (1, 3, 6, 10) in answer
/// paint, thinner each level.
class _RoadArt extends CustomPainter {
  _RoadArt({required this.colors, required this.level});

  final PindoroColors colors;
  final int level;

  static const _highlighted = [1, 3, 6, 10];
  static const _width = [18.0, 11.0, 6.0, 3.0];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.mapBasemapLand);
    final road = Paint()
      ..color = colors.mapBasemapRoad
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final casing = Paint()
      ..color = colors.mapBasemapCasing
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final lines = <(Offset, Offset)>[
      for (var i = 1; i <= 4; i++)
        (
          Offset(0, size.height * i / 5),
          Offset(size.width, size.height * i / 5),
        ),
      for (var i = 1; i <= 6; i++)
        (
          Offset(size.width * i / 7, 0),
          Offset(size.width * i / 7, size.height),
        ),
    ];
    for (final (a, b) in lines) {
      canvas
        ..drawLine(a, b, casing)
        ..drawLine(a, b, road);
    }
    final paint = Paint()
      ..color = colors.mapAnswerLine
      ..strokeWidth = _width[level - 1]
      ..strokeCap = StrokeCap.round;
    // A fixed order so each level adds roads to the previous one.
    const order = [1, 7, 3, 5, 0, 9, 2, 6, 4, 8];
    for (final i in order.take(_highlighted[level - 1])) {
      final (a, b) = lines[i];
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(_RoadArt old) =>
      old.level != level || old.colors != colors;
}

enum DistrictProgress { notStarted, inProgress, complete }

/// The city's districts filling in as streets become known: outline when not
/// started, yellow in progress, cobalt complete. Decorative; rows beside it
/// carry the same data.
class DistrictMiniMap extends StatelessWidget {
  const DistrictMiniMap({
    super.key,
    required this.districts,
    this.height = 120,
  });

  final List<({List<List<Polyline>> boundary, DistrictProgress progress})>
  districts;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(PindoroRadius.lg),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _DistrictPainter(
            colors: PindoroTheme.of(context).colors,
            districts: districts,
          ),
        ),
      ),
    ),
  );
}

class _DistrictPainter extends CustomPainter {
  _DistrictPainter({required this.colors, required this.districts});

  final PindoroColors colors;
  final List<({List<List<Polyline>> boundary, DistrictProgress progress})>
  districts;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.mapBasemapLand);
    final points = [
      for (final d in districts)
        for (final polygon in d.boundary)
          for (final ring in polygon) ...ring,
    ];
    if (points.isEmpty) return;
    final box = Bbox.of(points);
    // Equirectangular with the latitude's cosine, fitted and centred.
    final kx = math.cos(box.center.lat * math.pi / 180);
    final w = (box.maxLon - box.minLon) * kx, h = box.maxLat - box.minLat;
    final scale =
        0.92 *
        (size.width / w < size.height / h ? size.width / w : size.height / h);
    final dx = (size.width - w * scale) / 2, dy = (size.height - h * scale) / 2;
    Offset at(LatLng p) => Offset(
      dx + (p.lon - box.minLon) * kx * scale,
      dy + (box.maxLat - p.lat) * scale,
    );
    for (final d in districts) {
      final (fill, stroke, width) = switch (d.progress) {
        DistrictProgress.notStarted => (null, colors.mapRegionOutline, 1.5),
        DistrictProgress.inProgress => (
          colors.mapDistrictProgressFill,
          colors.mapDistrictProgressStroke,
          2.0,
        ),
        DistrictProgress.complete => (
          colors.mapDistrictMasteredFill,
          colors.mapDistrictMasteredStroke,
          2.0,
        ),
      };
      for (final polygon in d.boundary) {
        final path = Path()..fillType = PathFillType.evenOdd;
        for (final ring in polygon) {
          path.addPolygon([for (final p in ring) at(p)], true);
        }
        if (fill != null) canvas.drawPath(path, Paint()..color = fill);
        canvas.drawPath(
          path,
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DistrictPainter old) =>
      old.colors != colors || old.districts != districts;
}

/// A 6 dp bar of a district's known streets.
class Minibar extends StatelessWidget {
  const Minibar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: c.xpTrack,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1),
        child: Container(
          decoration: BoxDecoration(
            color: c.xpFill,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// A legend square for [DistrictMiniMap].
class Swatch extends StatelessWidget {
  const Swatch({super.key, required this.progress, required this.label});

  final DistrictProgress progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (fill, stroke) = switch (progress) {
      DistrictProgress.notStarted => (c.surfaceRaised, c.mapRegionOutline),
      DistrictProgress.inProgress => (
        c.mapDistrictProgressFill,
        c.mapDistrictProgressStroke,
      ),
      DistrictProgress.complete => (
        c.mapDistrictMasteredFill,
        c.mapDistrictMasteredStroke,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: PindoroSpace.s1,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: stroke, width: PindoroStroke.base),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Flexible(
          child: Text(
            label,
            style: PindoroType.labelMd.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}
