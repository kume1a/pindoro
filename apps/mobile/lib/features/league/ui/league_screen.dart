import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/features/league/data/league_api.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro/features/league/ui/league_name_form.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The `select` key of a tier's name in the strings.
String leagueTierKey(int tier) => const [
  'alley',
  'lane',
  'street',
  'avenue',
  'boulevard',
  'highway',
][tier.clamp(0, LeagueRules.tiers - 1)];

/// "Avenue league".
String leagueTitle(AppLocalizations l10n, int tier) =>
    l10n.leagueTitle(leagueTierKey(tier));

/// The Leagues tab (canvas R5-01): the name to join with, then this week's
/// league with its zones.
class LeagueScreen extends ConsumerWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(standingProvider);
    return PageScaffold(
      showBack: false,
      children: switch (standing) {
        // A failed sync says so, even over last time's board.
        AsyncValue(hasError: true, isLoading: false, :final error) => [
          _Note(
            pindo: PindoExpression.encouraging,
            title: leagueFailure(
              context.l10n,
              error!,
              context.l10n.leagueOffline,
            ),
            action: PindoroButton(
              label: context.l10n.commonTryAgain,
              onPressed: () => ref.invalidate(standingProvider),
            ),
          ),
        ],
        AsyncValue(hasValue: true, :final value) => switch (value) {
          null => [_Join(onJoin: ref.read(leagueActionsProvider).join)],
          final standing => _league(context, standing),
        },
        _ => [
          const Padding(
            padding: EdgeInsets.only(top: PindoroSpace.s16),
            child: Center(child: LaneLoader()),
          ),
        ],
      },
    );
  }

  List<Widget> _league(BuildContext context, Standing standing) {
    final l10n = context.l10n;
    final members = standing.members;
    final tier = standing.tier;
    final rule = tier == LeagueRules.tiers - 1
        ? l10n.leagueRuleDown
        : l10n.leagueRuleUp;
    final days = l10n.leagueDaysLeft(
      // Past the week's end while offline, the board is last week's.
      math.max(0, standing.endsAt.difference(DateTime.now()).inDays),
    );
    final title = leagueTitle(l10n, tier);
    String tierName(int t) => l10n.leagueTierName(leagueTierKey(t));
    return [
      LeagueHeader(
        title: title,
        subtitle: '$rule · $days',
        tier: tier,
        tiers: LeagueRules.tiers,
        semanticLabel: l10n.leagueHeadA11y(
          title,
          formatOrdinal(tier + 1, l10n),
          LeagueRules.tiers,
          rule,
          days,
        ),
      ),
      if (members.isEmpty)
        _Note(
          pindo: PindoExpression.happy,
          title: l10n.leagueEmptyTitle,
          body: l10n.leagueEmptyBody,
        )
      else
        Semantics(
          container: true,
          label: l10n.leagueListA11y(members.length),
          child: ListGroup(
            children: [
              for (final (i, m) in members.indexed) ...[
                if (m.zone == LeagueZone.down &&
                    (i == 0 || members[i - 1].zone != LeagueZone.down))
                  ZoneDivider(
                    label: l10n.leagueZoneDown(tierName(tier - 1)),
                    up: false,
                  ),
                _row(l10n, m),
                if (m.zone == LeagueZone.up &&
                    i + 1 < members.length &&
                    members[i + 1].zone != LeagueZone.up)
                  ZoneDivider(
                    label: l10n.leagueZoneUp(tierName(tier + 1)),
                    up: true,
                  ),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _row(AppLocalizations l10n, LeagueMember m) {
    final name = m.you ? l10n.leagueYou : m.name;
    final xp = formatNumber(m.xp);
    return LeagueRow(
      rank: m.rank,
      name: name,
      xp: l10n.leagueXp(xp),
      initials: initialsOf(m.name),
      avatar: m.name.codeUnits.fold(0, (sum, unit) => sum + unit),
      you: m.you,
      semanticLabel: l10n.leagueRowA11y(
        formatOrdinal(m.rank, l10n),
        name,
        xp,
        l10n.leagueZoneA11y(m.zone.name),
      ),
    );
  }
}

/// The first letter of the name's first two words, as typed ("Nino K." →
/// "NK"); never changes case (Georgian has no capitals to change to).
String initialsOf(String name) => name
    .split(' ')
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => String.fromCharCode(w.runes.first))
    .join();

class _Join extends StatelessWidget {
  const _Join({required this.onJoin});

  final Future<void> Function(String name) onJoin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Note(
      pindo: PindoExpression.happy,
      title: l10n.leagueJoinTitle,
      body: l10n.leagueJoinBody,
      action: LeagueNameForm(
        action: l10n.leagueJoin,
        failed: l10n.leagueJoinFailed,
        onSubmit: onJoin,
      ),
    );
  }
}

/// Pindo over a title, an optional line and an optional action.
class _Note extends StatelessWidget {
  const _Note({
    required this.pindo,
    required this.title,
    this.body,
    this.action,
  });

  final PindoExpression pindo;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(top: PindoroSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Pindo(pindo, height: 96),
          Text(
            title,
            textAlign: TextAlign.center,
            style: PindoroType.headlineSm.copyWith(color: c.textPrimary),
          ),
          if (body case final body?)
            Text(
              body,
              textAlign: TextAlign.center,
              style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
            ),
          if (action case final action?)
            Padding(
              padding: const EdgeInsets.only(top: PindoroSpace.s3),
              child: action,
            ),
        ],
      ),
    );
  }
}
