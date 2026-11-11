import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';

part 'league_dao.g.dart';

final leagueDaoProvider = Provider<LeagueDao>(
  (ref) => LeagueDao(ref.watch(databaseProvider)),
);

/// The league account row (`league_player`).
@DriftAccessor(tables: [LeaguePlayers])
class LeagueDao extends DatabaseAccessor<AppDatabase> with _$LeagueDaoMixin {
  LeagueDao(super.attachedDatabase);

  Stream<LeaguePlayer?> watchAccount() =>
      select(leaguePlayers).watchSingleOrNull();

  Future<void> save({
    required String playerId,
    required String token,
    required String name,
  }) => into(leaguePlayers).insertOnConflictUpdate(
    LeaguePlayersCompanion.insert(
      id: const Value(1),
      playerId: playerId,
      token: token,
      name: name,
    ),
  );

  Future<void> rename(String name) =>
      update(leaguePlayers).write(LeaguePlayersCompanion(name: Value(name)));

  Future<void> drop() => delete(leaguePlayers).go();
}
