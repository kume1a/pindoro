import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Months the route stair shows at most (RouteLevelStair).
const int _stairMonths = 12;

/// Drives on Progress (board V32-70, SPEC §16.23 item 123), once there is a drive: this week's
/// line, and each frequent route's level history in words and as a stair by month, opening its
/// past drives.
class ProgressDrives extends ConsumerWidget {
  const ProgressDrives({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final history = ref.watch(driveHistoryProvider).value;
    if (history == null || history.drives.isEmpty) {
      return const SizedBox.shrink();
    }
    final settings = ref.watch(settingsProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final places = ref.watch(packRepositoryProvider).value?.landmarks() ?? [];
    final week = ref.watch(driveWeekLineProvider).value;
    final routes = ref.watch(routeLevelsProvider).value ?? const [];
    final now = ref.watch(clockProvider)().toLocal();
    final locale = Localizations.localeOf(context).toLanguageTag();
    String month(DateTime m) => DateFormat.MMMM(locale).format(m);
    final own = week?.own;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s3,
      children: [
        SectionTitle(l10n.progressDrives),
        Text(
          week == null
              ? l10n.progressDrivesNone
              : l10n.progressDrivesWeek(
                  [
                    l10n.progressDrivesFree(week.drives),
                    l10n.progressDrivesPlaces(week.places),
                    if (own != null)
                      l10n.progressDrivesOwn(formatNumber((100 * own).round())),
                  ].join(', '),
                ),
          style: PindoroType.bodyMd.copyWith(color: c.textPrimary),
        ),
        for (final r in routes)
          () {
            final name = routeName(
              l10n,
              r.route,
              places: places,
              streets: streets,
              settings: settings,
            );
            final words = _history(l10n, levelRuns(r.months), month);
            final levels = {for (final m in r.months) m.month: m.level};
            final first = r.months.first.month;
            final span = (now.year - first.year) * 12 + now.month - first.month;
            final count = (span + 1).clamp(1, _stairMonths);
            return Semantics(
              button: true,
              label: l10n.a11yRouteCard(name, r.drives, words),
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () =>
                    unawaited(context.push(Routes.pastDrivesOf(r.route))),
                child: TitledCard(
                  title: name,
                  meta: l10n.progressRouteDrives(r.drives),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: PindoroSpace.s3,
                    children: [
                      Text(
                        words,
                        style: PindoroType.bodySm.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      RouteLevelStair(
                        semanticsLabel: words,
                        months: [
                          for (var i = count - 1; i >= 0; i--)
                            () {
                              final m = DateTime(now.year, now.month - i);
                              return (
                                month: DateFormat.MMM(locale).format(m),
                                level: levels[m]?.index,
                              );
                            }(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// "Guided in March, Off since June": a route's runs of one level, the last one ongoing.
String _history(
  AppLocalizations l10n,
  List<({DriveLevel level, DateTime from, DateTime to})> runs,
  String Function(DateTime) month,
) => [
  for (final (i, r) in runs.indexed)
    i == runs.length - 1
        ? l10n.progressRouteSince(levelLabel(l10n, r.level), month(r.from))
        : r.from == r.to
        ? l10n.progressRouteIn(levelLabel(l10n, r.level), month(r.from))
        : l10n.progressRouteFromTo(
            levelLabel(l10n, r.level),
            month(r.from),
            month(r.to),
          ),
].join(', ');
