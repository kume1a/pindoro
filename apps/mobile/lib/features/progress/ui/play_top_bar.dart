import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/progress/ui/streak_pill.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A tab's top row: the city switcher (opens the city picker), then
/// [trailing] (Today: the streak pill, Explore: settings).
class PlayTopBar extends StatelessWidget {
  const PlayTopBar({super.key, required this.city, required this.trailing});

  final City city;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cityName = context.localName(ka: city.nameKa, en: city.nameEn);
    return ContentColumn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PindoroSpace.s4,
          PindoroSpace.s2,
          PindoroSpace.s4,
          0,
        ),
        child: Row(
          spacing: PindoroSpace.s2,
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: CitySwitcher(
                  city: cityName,
                  semanticLabel: l10n.a11yCitySwitcher(cityName),
                  onPressed: () => context.push(Routes.city),
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// The streak pill for a top bar; opens Streak.
class StreakPillButton extends ConsumerWidget {
  const StreakPillButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(streakProvider).value) {
        final streak? => TopStreakPill(
          streak,
          onPressed: () => context.push(Routes.streak),
        ),
        null => const SizedBox.shrink(),
      };
}
