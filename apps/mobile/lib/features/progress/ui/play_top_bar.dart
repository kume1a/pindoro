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

/// The top row of Free play and the Path: the city switcher (opens the city
/// picker), the streak pill (opens Streak) and [xp], the XP pill.
class PlayTopBar extends ConsumerWidget {
  const PlayTopBar({super.key, required this.city, required this.xp});

  final City city;
  final Widget xp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final streak = ref.watch(streakProvider).value;
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
            if (streak != null)
              TopStreakPill(
                streak,
                onPressed: () => context.push(Routes.streak),
              ),
            xp,
          ],
        ),
      ),
    );
  }
}

/// The total XP in the top bar.
class XpPill extends StatelessWidget {
  const XpPill(this.totalXp, {super.key, this.shown, this.ring = false});

  final int totalXp;

  /// The value drawn (a count-up's frame); [totalXp] when null.
  final int? shown;
  final bool ring;

  @override
  Widget build(BuildContext context) => Pill(
    label: formatNumber(shown ?? totalXp),
    icon: PindoroGlyph.xp,
    iconColor: PindoroTheme.of(context).colors.xpFill,
    ring: ring,
    semanticLabel: context.l10n.homeXpTotal(formatNumber(totalXp)),
  );
}
