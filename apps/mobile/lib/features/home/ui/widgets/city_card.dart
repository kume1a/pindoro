import 'package:flutter/material.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/home/data/home_data.dart';
import 'package:pindoro/features/home/ui/widgets/home_coach.dart';
import 'package:pindoro/features/home/ui/widgets/home_intro.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

DistrictProgress _progress(KnownCount c) => c.known == 0
    ? DistrictProgress.notStarted
    : c.known >= c.total
    ? DistrictProgress.complete
    : DistrictProgress.inProgress;

/// The city's districts (not neighbourhoods), filled by each one's [count].
DistrictMiniMap _miniMap(
  List<DistrictCount> districts,
  KnownCount Function(DistrictCount d) count,
) => DistrictMiniMap(
  districts: [
    for (final d in districts)
      if (d.district.kind == DistrictKind.district)
        (boundary: d.district.boundary, progress: _progress(count(d))),
  ],
);

class CityCard extends StatelessWidget {
  const CityCard({
    super.key,
    required this.home,
    required this.settings,
    required this.onDistrict,
    required this.onAll,
    required this.onCoachClosed,
    this.intro,
  });

  final HomeData home;
  final HomeIntro? intro;
  final Settings? settings;
  final VoidCallback onCoachClosed;
  final ValueChanged<String> onDistrict;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final known = home.cityKnown;
    final before = intro?.before;
    final newlyKnown = known.known - (before?.city.known ?? known.known);
    return LipBox(
      border: c.lineBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Row(
            spacing: PindoroSpace.s2,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: HomeCoach(
                    show: !(settings?.homeCoachSeen ?? true),
                    onClose: onCoachClosed,
                    child: Text(
                      l10n.homeKnownTitle,
                      style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
              ),
              if (newlyKnown > 0)
                PopIn(
                  delay: HomeIntroAt.streets,
                  child: Pill(label: '+${formatNumber(newlyKnown)}'),
                ),
              CountUp(
                value: known.known,
                from: before?.city.known ?? known.known,
                delay: HomeIntroAt.streets,
                builder: (context, n) => Text(
                  l10n.homeKnownOf(formatNumber(n), formatNumber(known.total)),
                  style: PindoroType.numericMd.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          if (home.districts.isNotEmpty) ...[
            if (before == null)
              _miniMap(home.districts, (d) => d.count)
            else
              // Districts that changed state fade in with the streets.
              Stack(
                children: [
                  _miniMap(
                    home.districts,
                    (d) =>
                        before.byDistrict[d.district.id] ??
                        (known: 0, total: 0),
                  ),
                  Builder(
                    builder: (context) {
                      final (duration, curve) = delayedMotion(
                        context,
                        HomeIntroAt.streets,
                        PindoroMotion.durationQuick,
                        Curves.linear,
                      );
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: duration,
                        curve: curve,
                        builder: (_, t, child) =>
                            Opacity(opacity: t, child: child),
                        child: _miniMap(home.districts, (d) => d.count),
                      );
                    },
                  ),
                ],
              ),
            Wrap(
              spacing: PindoroSpace.s4,
              runSpacing: PindoroSpace.s1,
              children: [
                Swatch(
                  progress: DistrictProgress.inProgress,
                  label: l10n.homeLegendInProgress,
                ),
                Swatch(
                  progress: DistrictProgress.complete,
                  label: l10n.homeLegendComplete,
                ),
                Swatch(
                  progress: DistrictProgress.notStarted,
                  label: l10n.homeLegendNotStarted,
                ),
              ],
            ),
          ],
          if (known.known == 0)
            Text(
              l10n.homeEmptyCity,
              style: PindoroType.bodySm.copyWith(color: c.textSecondary),
            ),
          for (final d in home.recent)
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => onDistrict(d.district.id),
                mouseCursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: PindoroSpace.s2,
                  ),
                  child: Row(
                    spacing: PindoroSpace.s3,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          districtName(d.district, settings),
                          style: PindoroType.titleSm.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Minibar(
                          value: d.count.fraction,
                          from: before?.byDistrict[d.district.id]?.fraction,
                          delay: HomeIntroAt.streets,
                        ),
                      ),
                      Text(
                        '${formatNumber(d.count.known)} / '
                        '${formatNumber(d.count.total)}',
                        style: PindoroType.numericSm.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (home.districts.isNotEmpty)
            PindoroButton(
              label: l10n.homeAllDistricts(home.districts.length),
              variant: PindoroButtonVariant.tertiary,
              onPressed: onAll,
            ),
        ],
      ),
    );
  }
}
