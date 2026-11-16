import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro/features/badges/ui/badge_look.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The reward moment's shield (component Badge).
const double _rewardShield = 110;

/// One reward sheet per badge in [ids], one after another; closing one any
/// way marks it seen.
Future<void> showBadgeRewards(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  for (final id in ids) {
    if (!context.mounted) return;
    ref.read(feedbackProvider).badge();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: PindoroTheme.of(context).colors.rewardSoft,
      builder: (_) => _BadgeRewardSheet(id),
    );
    await ref.read(progressDaoProvider).seeBadges([id], DateTime.now());
  }
}

/// The reward sheet on `color.reward.soft`: the shield pops in a 12-dash
/// burst, "Badge unlocked", the badge and its condition, Nice!.
class _BadgeRewardSheet extends StatelessWidget {
  const _BadgeRewardSheet(this.id);

  /// The stored badge id.
  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final look = badgeLook(context, id);
    return Stack(
      children: [
        const Positioned.fill(
          child: Celebration(
            size: CelebrationSize.medium,
            burstCenter: Alignment(0, -0.5),
          ),
        ),
        Padding(
          // Nice! stays clear of the gesture bar, as every primary action.
          padding: EdgeInsets.fromLTRB(
            PindoroSpace.s5,
            PindoroSpace.s6,
            PindoroSpace.s5,
            bottomActionGap(context),
          ),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                Center(
                  child: PopIn(
                    child: BadgeShield(
                      glyph: look.glyph,
                      field: look.field,
                      size: _rewardShield,
                    ),
                  ),
                ),
                Text(
                  l10n.badgeUnlocked,
                  textAlign: TextAlign.center,
                  style: PindoroType.headlineLg.copyWith(color: c.rewardText),
                ),
                Text(
                  l10n.badgeRewardBody(look.name, look.condition),
                  textAlign: TextAlign.center,
                  style: PindoroType.bodyLg.copyWith(color: c.textPrimary),
                ),
                PindoroButton(
                  label: l10n.badgeNice,
                  variant: PindoroButtonVariant.reward,
                  hero: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// For an end screen: awards this play's badges as it opens (its play is
/// saved by then) and shows their reward sheets once [showBadgesAfter] is
/// first called, after the arrival.
mixin BadgeMoments<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final Future<List<String>> _earned;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    // A failed award (a pack that won't open) tries again at the next end
    // screen; the screen itself never fails for it.
    _earned = ref.read(awardBadgesProvider)().onError((_, _) => const []);
  }

  void showBadgesAfter(Duration delay) {
    if (_scheduled) return;
    _scheduled = true;
    unawaited(() async {
      final ids = await _earned;
      if (ids.isEmpty) return;
      await Future<void>.delayed(delay);
      if (mounted) await showBadgeRewards(context, ref, ids);
    }());
  }
}
