import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/ui/play_top_bar.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A city tab (Today, Progress; canvas V31-99 decision 3): the shared top
/// bar, the city switcher and the streak pill, over [children] in a
/// scrolling column, [PindoroSpace.s4] apart.
class CityTabPage extends ConsumerWidget {
  const CityTabPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(packRepositoryProvider).value?.city();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (city != null)
              PlayTopBar(city: city, trailing: const StreakPillButton()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PindoroSpace.s4),
                children: [
                  for (final child in children)
                    ContentColumn(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: PindoroSpace.s4),
                        child: child,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The district fills' legend (District fills): not started, under a
/// quarter, a quarter or more, Mastered. Hidden from screen readers: the map
/// says the same. [dense] is the key over Explore's map.
class DistrictLegend extends StatelessWidget {
  const DistrictLegend({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ExcludeSemantics(
      child: Wrap(
        spacing: dense ? PindoroSpace.s2 : PindoroSpace.s3,
        runSpacing: dense ? PindoroSpace.s1 : PindoroSpace.s2,
        children: [
          for (final (progress, label) in [
            (DistrictProgress.notStarted, l10n.legendNotStarted),
            (DistrictProgress.started, l10n.legendStarted),
            (DistrictProgress.inProgress, l10n.legendInProgress),
            (DistrictProgress.complete, l10n.memoryMastered),
          ])
            Swatch(
              progress: progress,
              label: label,
              size: dense ? 12 : 16,
              dense: dense,
            ),
        ],
      ),
    );
  }
}
