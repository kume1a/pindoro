import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';

part 'account_dao.g.dart';

final accountDaoProvider = Provider<AccountDao>(
  (ref) => AccountDao(ref.watch(databaseProvider)),
);

/// The backup account row (`account`).
@DriftAccessor(tables: [Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.attachedDatabase);

  Stream<Account?> watchAccount() => select(accounts).watchSingleOrNull();

  Future<Account?> read() => select(accounts).getSingleOrNull();

  /// Signs this phone in: [backedUpAt] after a restore (the backup holds this
  /// phone's progress), [changedAt] when this phone's progress must go up.
  Future<void> save({
    required String username,
    required String token,
    DateTime? backedUpAt,
    DateTime? changedAt,
  }) => into(accounts).insertOnConflictUpdate(
    AccountsCompanion.insert(
      id: const Value(1),
      username: username,
      token: Value(token),
      backedUpAt: Value(backedUpAt),
      changedAt: Value(changedAt),
    ),
  );

  /// The first write the backup lacks.
  Future<void> markChanged(DateTime at) =>
      (update(accounts)..where((a) => a.changedAt.isNull())).write(
        AccountsCompanion(changedAt: Value(at)),
      );

  /// A backup went up; it holds every write when [complete].
  Future<void> markBackedUp(DateTime at, {required bool complete}) =>
      update(accounts).write(
        AccountsCompanion(
          backedUpAt: Value(at),
          changedAt: complete ? const Value(null) : const Value.absent(),
        ),
      );

  /// A sign-in on another phone took over: the username stays for signing
  /// in again here.
  Future<void> signedOutElsewhere() =>
      update(accounts).write(const AccountsCompanion(token: Value(null)));

  Future<void> drop() => delete(accounts).go();
}
