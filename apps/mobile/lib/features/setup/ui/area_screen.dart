import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/pack/ui/pack_pending.dart';
import 'package:pindoro/features/setup/ui/area_map.dart';
import 'package:pindoro/features/setup/ui/widgets/all_areas_sheet.dart';
import 'package:pindoro/features/setup/ui/widgets/area_sheet.dart';
import 'package:pindoro/features/setup/ui/widgets/shape_overlays.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

const double _metresPerDegree = 111195;

/// Unpicked chips in the sheet: the areas nearest the map's centre.
const int _nearbyChips = 6;

/// Each district with the neighbourhoods whose centre lies in it (else the
/// nearest district), districts by name.
List<({District district, List<District> parts})> groupByDistrict(
  List<District> areas,
) {
  final districts = [
    for (final d in areas)
      if (d.kind == DistrictKind.district) d,
  ];
  final parts = {for (final d in districts) d.id: <District>[]};
  for (final n in areas) {
    if (n.kind == DistrictKind.district || districts.isEmpty) continue;
    final home =
        districts
            .where((d) => d.boundary.any((p) => polygonContains(p, n.center)))
            .firstOrNull ??
        (districts.toList()..sort(
              (a, b) => distanceBetween(
                n.center,
                a.center,
              ).compareTo(distanceBetween(n.center, b.center)),
            ))
            .first;
    parts[home.id]!.add(n);
  }
  return [for (final d in districts) (district: d, parts: parts[d.id]!)];
}

/// Where the round's streets come from: districts, a circle or a rectangle.
/// Circle and rectangle stay in the middle of the map; the map pans under
/// them.
class AreaScreen extends ConsumerStatefulWidget {
  const AreaScreen({super.key});

  @override
  ConsumerState<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends ConsumerState<AreaScreen> {
  AreaMode? _mode;
  Set<String> _picked = {};
  double _radiusM = 2000;
  double _widthM = 2600;
  double _heightM = 3000;
  LatLng? _center;
  double _zoom = PindoroCamera.zoom;
  Bbox? _focus;
  bool _seeded = false;

  void _seedFrom(Settings? settings, PackRepository pack) {
    if (_seeded) return;
    _seeded = true;
    final known = {for (final d in pack.districts()) d.id};
    _center = pack.city().center;
    switch (settings?.lastCity == pack.city().id ? settings?.area : null) {
      case DistrictsArea(:final ids) when known.isNotEmpty:
        _mode = AreaMode.districts;
        // Areas this pack lacks (offline stand-in, retired) are dropped.
        _picked = ids.intersection(known);
      case CircleArea(:final center, :final radiusM):
        _mode = AreaMode.circle;
        _radiusM = radiusM;
        _center = center;
        _focus = CircleArea(center, radiusM).bbox;
      case RectArea(:final bounds):
        _mode = AreaMode.rectangle;
        _widthM = _side(bounds, horizontal: true);
        _heightM = _side(bounds, horizontal: false);
        _focus = bounds;
        _center = bounds.center;
      default:
        _mode = known.isNotEmpty ? AreaMode.districts : AreaMode.circle;
    }
  }

  static double _side(Bbox b, {required bool horizontal}) => horizontal
      ? distanceBetween(
          LatLng(b.center.lat, b.minLon),
          LatLng(b.center.lat, b.maxLon),
        )
      : distanceBetween(
          LatLng(b.minLat, b.center.lon),
          LatLng(b.maxLat, b.center.lon),
        );

  /// A new mode starts from the old shape: districts become the circle
  /// around them, a circle the rectangle around it, and back.
  void _switchMode(AreaMode next, PackRepository pack) {
    ref.read(feedbackProvider).tap();
    setState(() {
      switch ((_mode, next)) {
        case (AreaMode.districts, AreaMode.circle || AreaMode.rectangle)
            when _picked.isNotEmpty:
          final box = DistrictsArea(_picked).shapeIn(pack)?.bbox;
          if (box != null) {
            final half = math.max(
              _side(box, horizontal: true),
              _side(box, horizontal: false),
            );
            _radiusM = _clampRadius(half / 2);
            _widthM = _clampSide(_side(box, horizontal: true));
            _heightM = _clampSide(_side(box, horizontal: false));
            _focus = box;
          }
        case (AreaMode.circle, AreaMode.rectangle):
          _widthM = _heightM = _clampSide(2 * _radiusM);
        case (AreaMode.rectangle, AreaMode.circle):
          _radiusM = _clampRadius(math.min(_widthM, _heightM) / 2);
        default:
      }
      _mode = next;
    });
  }

  static double _clampRadius(double m) => ((m / 500).round() * 500.0).clamp(
    CircleArea.minRadiusM,
    CircleArea.maxRadiusM,
  );

  static double _clampSide(double m) =>
      ((m / 100).round() * 100.0).clamp(RectArea.minSideM, RectArea.maxSideM);

  void _toggle(String id) {
    ref.read(feedbackProvider).tap();
    setState(() {
      _picked = {..._picked};
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  /// The 90 % sheet with every area, grouped by district, and a search.
  Future<void> _showAll(List<District> areas, Map<String, String> names) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.9,
          child: StatefulBuilder(
            builder: (context, setSheetState) => AllAreasSheet(
              groups: groupByDistrict(areas),
              names: names,
              picked: _picked,
              onToggle: (id) {
                _toggle(id);
                setSheetState(() {});
              },
            ),
          ),
        ),
      );

  Area? _area() {
    final center = _center;
    return switch (_mode) {
      AreaMode.districts => _picked.isEmpty ? null : DistrictsArea(_picked),
      AreaMode.circle when center != null => CircleArea(center, _radiusM),
      AreaMode.rectangle when center != null => RectArea(
        Bbox(
          center.lat - _heightM / 2 / _metresPerDegree,
          center.lon -
              _widthM /
                  2 /
                  (_metresPerDegree * math.cos(center.lat * math.pi / 180)),
          center.lat + _heightM / 2 / _metresPerDegree,
          center.lon +
              _widthM /
                  2 /
                  (_metresPerDegree * math.cos(center.lat * math.pi / 180)),
        ),
      ),
      _ => null,
    };
  }

  Future<void> _next(PackRepository pack) async {
    final area = _area();
    if (area == null) return;
    await ref
        .read(settingsDaoProvider)
        .chooseArea(area, cityId: pack.city().id);
    if (mounted) await context.push(Routes.difficulty);
  }

  @override
  Widget build(BuildContext context) {
    final packState = ref.watch(packRepositoryProvider);
    final pack = packState.value;
    final settings = ref.watch(settingsProvider).value;
    if (pack == null || settings == null) {
      return PackPending(pack: packState);
    }
    final offline = isFixturePack(pack);
    _seedFrom(settings, pack);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final districts = pack.districts();
    final city = pack.city();
    final georgian = locale.languageCode == 'ka';
    final mode = _mode!;
    final mpp = metresPerPixel(_zoom, _center?.lat ?? city.center.lat);

    final names = {for (final d in districts) d.id: districtName(d, settings)};
    final here = _center ?? city.center;
    final level = levelAt(_zoom);
    final picked = [
      for (final d in districts)
        if (_picked.contains(d.id)) d,
    ]..sort((a, b) => names[a.id]!.compareTo(names[b.id]!));
    // The zoom's level first, then the nearest to the map's centre.
    final nearest =
        [
          for (final d in districts)
            if (!_picked.contains(d.id)) d,
        ]..sort((a, b) {
          final byLevel = (a.kind == level ? 0 : 1).compareTo(
            b.kind == level ? 0 : 1,
          );
          return byLevel != 0
              ? byLevel
              : distanceBetween(
                  here,
                  a.center,
                ).compareTo(distanceBetween(here, b.center));
        });
    final pickedNames = [for (final d in picked) names[d.id]!];

    final (title, help) = switch (mode) {
      AreaMode.districts => (
        _picked.isEmpty ? l10n.areaNoneTitle : districtNames(l10n, pickedNames),
        offline ? l10n.areaOffline : l10n.areaHelp,
      ),
      AreaMode.circle => (
        '${l10n.areaPlayArea} · ${formatSize(_radiusM, locale)}',
        l10n.areaCircleHelp,
      ),
      AreaMode.rectangle => (
        '${l10n.areaPlayArea} · ${formatSides(_widthM, _heightM, locale)}',
        l10n.areaRectangleHelp,
      ),
    };

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ref.watch(areaPickerMapBuilderProvider)(
                  AreaPickerMap(
                    // A new pack (first download, update) rebuilds the layers.
                    key: ObjectKey(pack),
                    districts: districts,
                    names: names,
                    picked: mode == AreaMode.districts ? _picked : const {},
                    initialBounds: city.bbox,
                    focus: _focus,
                    showDistricts: mode == AreaMode.districts,
                    onTap: (at) {
                      if (mode != AreaMode.districts) return;
                      if (areaAt(districts, at, _zoom) case final d?) {
                        _toggle(d.id);
                      }
                    },
                    onCamera: (center, zoom) => setState(() {
                      _center = center;
                      _zoom = zoom;
                    }),
                  ),
                ),
                if (mode == AreaMode.circle)
                  Positioned.fill(
                    child: CircleOverlay(
                      radiusPx: _radiusM / mpp,
                      label: formatSize(_radiusM, locale),
                      onResize: (px) {
                        final r = _clampRadius(px * mpp);
                        if (r != _radiusM) {
                          ref.read(feedbackProvider).tap();
                          setState(() => _radiusM = r);
                        }
                      },
                    ),
                  ),
                if (mode == AreaMode.rectangle)
                  Positioned.fill(
                    child: RectOverlay(
                      size: Size(_widthM / mpp, _heightM / mpp),
                      label: formatSides(_widthM, _heightM, locale),
                      onResize: (size) => setState(() {
                        _widthM = _clampSide(size.width * mpp);
                        _heightM = _clampSide(size.height * mpp);
                      }),
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(PindoroSpace.s4),
                    child: Row(
                      spacing: PindoroSpace.s3,
                      children: [
                        MapControl(
                          glyph: PindoroGlyph.back,
                          semanticLabel: l10n.commonBack,
                          onPressed: context.pop,
                        ),
                        Pill(
                          label: georgian ? city.nameKa : city.nameEn,
                          icon: PindoroGlyph.city,
                          floating: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AreaSheet(
            modes: {
              if (districts.isNotEmpty)
                AreaMode.districts: l10n.areaModeDistricts,
              AreaMode.circle: l10n.areaModeCircle,
              AreaMode.rectangle: l10n.areaModeRectangle,
            },
            mode: mode,
            onMode: (m) => _switchMode(m, pack),
            title: title,
            help: help,
            count: mode == AreaMode.districts
                ? l10n.areaDistrictCount(districts.length, _picked.length)
                : null,
            all: offline
                ? PindoroButton(
                    label: l10n.commonTryAgain,
                    variant: PindoroButtonVariant.tertiary,
                    onPressed: () => ref.invalidate(packRepositoryProvider),
                  )
                : mode == AreaMode.districts
                ? PindoroChip(
                    label: l10n.areaAllChip(districts.length),
                    selected: false,
                    onPressed: () => _showAll(districts, names),
                  )
                : null,
            content: switch (mode) {
              AreaMode.districts => Wrap(
                spacing: PindoroSpace.s2,
                runSpacing: PindoroSpace.s2,
                children: [
                  for (final d in [...picked, ...nearest.take(_nearbyChips)])
                    PindoroChip(
                      label: names[d.id]!,
                      selected: _picked.contains(d.id),
                      onPressed: () => _toggle(d.id),
                    ),
                ],
              ),
              AreaMode.circle => Slider(
                value: _radiusM,
                min: CircleArea.minRadiusM,
                max: CircleArea.maxRadiusM,
                divisions: 9,
                label: formatSize(_radiusM, locale),
                semanticFormatterCallback: (v) => formatSize(v, locale),
                onChanged: (v) {
                  ref.read(feedbackProvider).tap();
                  setState(() => _radiusM = v);
                },
              ),
              AreaMode.rectangle => null,
            },
            next: PindoroButton(
              label: mode == AreaMode.districts && _picked.isEmpty
                  ? l10n.areaNoneButton
                  : l10n.commonNext,
              onPressed: _area() == null ? null : () => _next(pack),
            ),
          ),
        ],
      ),
    );
  }
}
