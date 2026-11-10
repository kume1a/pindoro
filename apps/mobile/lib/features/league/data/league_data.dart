import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/league/data/league_api.dart';
import 'package:pindoro/features/league/data/league_dao.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// The league account, null until the player joins.
final leagueAccountProvider = StreamProvider<LeaguePlayer?>(
  (ref) => ref.watch(leagueDaoProvider).watchAccount(),
);

/// This week's league after sending the week's XP; null without an account.
/// An unknown token (the player is gone on the server) drops the account.
/// Invalidate it to sync again (the Leagues tab and Results do).
final standingProvider = FutureProvider.autoDispose<Standing?>((ref) async {
  final account = await ref.watch(leagueAccountProvider.future);
  if (account == null) return null;
  final week = leagueWeek(DateTime.now());
  final xp = await ref
      .read(progressDaoProvider)
      .xpBetween(week.start, week.end);
  try {
    return await ref
        .read(leagueApiProvider)
        .sync(account.token, week: week.key, xp: xp);
  } on LeagueException catch (e) {
    if (!e.unknownPlayer) rethrow;
    await ref.read(leagueDaoProvider).drop();
    return null;
  }
});

final leagueActionsProvider = Provider<LeagueActions>(
  (ref) =>
      LeagueActions(ref.watch(leagueApiProvider), ref.watch(leagueDaoProvider)),
);

/// Joining, renaming and leaving: the server first, then the local account.
class LeagueActions {
  const LeagueActions(this._api, this._dao);

  final LeagueApi _api;
  final LeagueDao _dao;

  Future<void> join(String name) async {
    final player = await _api.join(name);
    await _dao.save(
      playerId: player.id,
      token: player.token,
      name: player.name,
    );
  }

  Future<void> rename(LeaguePlayer account, String name) async =>
      _dao.rename(await _api.rename(account.token, name));

  /// A player the server no longer knows is gone already.
  Future<void> leave(LeaguePlayer account) async {
    try {
      await _api.leave(account.token);
    } on LeagueException catch (e) {
      if (!e.unknownPlayer) rethrow;
    }
    await _dao.drop();
  }
}

/// The player's rank before their last [gained] XP, from the others' XP now
/// (an equal player ahead of them stays ahead); null when the player isn't
/// in [members] or that XP is what put them in the league.
int? rankBefore(List<LeagueMember> members, int gained) {
  final me = members.where((m) => m.you).firstOrNull;
  if (me == null) return null;
  final before = me.xp - gained;
  if (before <= 0) return null;
  return 1 +
      members
          .where(
            (m) =>
                !m.you &&
                (m.xp > before || (m.xp == before && m.rank < me.rank)),
          )
          .length;
}
