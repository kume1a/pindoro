import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/features/learning/ui/city_tab_page.dart';
import 'package:pindoro/features/today/ui/widgets/coming_up.dart';
import 'package:pindoro/features/today/ui/widgets/first_run.dart';
import 'package:pindoro/features/today/ui/widgets/today_card.dart';
import 'package:pindoro/features/today/ui/widgets/week_strips.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Today, the first tab (canvas V31-10): `firstRun` offers placement until
/// the city is placed; then the one thing to do now (`ready`, `catching up`
/// or `done`), City memory as a row, and what comes next: the run to drive,
/// the neighbourhood being learnt, the gateways, the next 7 days and any
/// mix-up to watch.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    Future<void> open(String route) async {
      await context.push(route);
      refreshLearning(ref);
    }

    final learnCity = ref.watch(learnCityProvider);
    final plan = ref.watch(todayPlanProvider);
    final memory = ref.watch(cityMemoryProvider).value;
    final cards = switch ((learnCity, plan)) {
      (AsyncData(value: final c), _) when c?.placedAt == null => [
        FirstRun(onOpen: open),
      ],
      (AsyncData(), AsyncData(value: final plan)) => () {
        // The day's minutes spent with reviews still due is a backlog with
        // nothing to start: done (SPEC §16.2).
        final done = plan.rounds.isEmpty;
        final catchingUp = plan.backlog && !done;
        final run = catchingUp ? null : ref.watch(todayRunProvider).value;
        final learning = ref.watch(nowLearningProvider).value;
        final raion = learning?.raion;
        final gateways = raion != null && !catchingUp && !done
            ? ref.watch(gatewaysProvider(raion.id)).value
            : null;
        final mixUps = catchingUp
            ? const <(NamedStreet, NamedStreet)>[]
            : ref.watch(mixUpsYesterdayProvider).value ?? const [];
        return [
          if (done)
            DoneForToday(
              tomorrow: ref.watch(dueTomorrowProvider).value ?? 0,
              onLearnMore: () => open(Routes.learnMore),
            )
          else if (catchingUp)
            CatchingUp(plan: plan, onStart: () => open(Routes.session))
          else
            TodaysDrive(plan: plan, onStart: () => open(Routes.session)),
          if (catchingUp) const MostOverdueFirst(),
          if (done) const LastWeek(),
          if (memory != null)
            CityMemoryRow(
              memory: memory.city,
              change: catchingUp
                  ? (
                      value: memory.sinceWeek,
                      label: memoryChange(l10n, memory.sinceWeek, week: true),
                    )
                  : (
                      value: memory.sinceYesterday,
                      label: memoryChange(
                        l10n,
                        memory.sinceYesterday,
                        firstDay: memory.firstDay,
                      ),
                    ),
              onTap: () => context.go(Routes.progress),
            ),
          SectionTitle(l10n.todayComingUp),
          if (run != null)
            DriveThisRun(run: run, onDrive: () => open(Routes.drive)),
          if (learning != null)
            NowLearningCard(
              learning: learning,
              paused: catchingUp,
              onTap: raion == null
                  ? () => context.go(Routes.progress)
                  : () => open(Routes.progressOf(raion.id)),
            ),
          if (raion != null && gateways != null && gateways.started)
            GatewaysCard(
              gateways: gateways,
              onTap: () => open(Routes.progressOf(raion.id)),
            ),
          NextWeek(plan: plan, done: done),
          if (mixUps.isNotEmpty) ...[
            SectionTitle(l10n.sessionDoneWatchOut),
            WatchOut(mixUps),
          ],
        ];
      }(),
      _ => const [Center(child: LaneLoader())],
    };
    return CityTabPage(children: cards);
  }
}
