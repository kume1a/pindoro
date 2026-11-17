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

/// A tab's top row: the city's name, then [trailing] (the streak pill).
/// [floating] over a map, the name sits in a raised capsule.
class PlayTopBar extends StatelessWidget {
  const PlayTopBar({
    super.key,
    required this.city,
    required this.trailing,
    this.floating = false,
  });

  final City city;
  final Widget trailing;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final name = SizedBox(
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
                context.localName(ka: city.nameKa, en: city.nameEn),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PindoroType.titleMd.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
                child: floating
                    ? LipBox(
                        radius: PindoroRadius.full,
                        shadow: true,
                        padding: const EdgeInsets.only(
                          left: PindoroSpace.s1,
                          right: PindoroSpace.s2,
                        ),
                        child: name,
                      )
                    : name,
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
