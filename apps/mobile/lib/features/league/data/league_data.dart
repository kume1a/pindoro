import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/features/account/data/account_dao.dart';
import 'package:pindoro/features/account/data/account_data.dart';
import 'package:pindoro/features/league/data/league_api.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// This week's league after sending the week's XP; null while signed out.
/// An unknown token (a sign-in on another phone) signs this phone out.
/// Invalidate it to sync again (the app root on resume, the Leagues tab, and
/// the end of a round, lesson or road trip do). A failure isn't retried on its
/// own: the next of those, or Try again, syncs.
final standingProvider = FutureProvider.autoDispose<Standing?>((ref) async {
  // The token only: a backup isn't a reason to sync.
  final token = await ref.watch(
    accountProvider.selectAsync((account) => account?.token),
  );
  if (token == null) return null;
  final week = leagueWeek(DateTime.now());
  final xp = await ref
      .read(progressDaoProvider)
      .xpBetween(week.start, week.end);
  try {
    return await ref
        .read(leagueApiProvider)
        .sync(token, week: week.key, xp: xp);
  } on ApiException catch (e) {
    if (!e.unknownToken) rethrow;
    await ref.read(accountDaoProvider).signedOutElsewhere();
    return null;
  }
}, retry: (_, _) => null);

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
