import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';

part 'account_dao.g.dart';

final accountDaoProvider = Provider<AccountDao>(
  (ref) => AccountDao(ref.watch(databaseProvider)),
);

/// The signed-in account row (`account`).
@DriftAccessor(tables: [Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.attachedDatabase);

  Stream<Account?> watch() => select(accounts).watchSingleOrNull();

  Future<Account?> read() => select(accounts).getSingleOrNull();

  Future<void> save({required String username, required String token}) =>
      into(accounts).insertOnConflictUpdate(
        AccountsCompanion.insert(
          id: const Value(1),
          username: username,
          token: token,
        ),
      );

  Future<void> markBackedUp(DateTime at) =>
      update(accounts).write(AccountsCompanion(backedUpAt: Value(at)));

  Future<void> drop() => delete(accounts).go();
}
