import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:spent/core/database/database.dart';

class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  $AccountsTable get _a => _db.accounts;

  Stream<List<Account>> watchAll() => (_db.select(
    _a,
  )..orderBy([(a) => OrderingTerm.asc(a.sortOrder), (a) => OrderingTerm.asc(a.id)])).watch();

  Future<List<Account>> all() => (_db.select(
    _a,
  )..orderBy([(a) => OrderingTerm.asc(a.sortOrder), (a) => OrderingTerm.asc(a.id)])).get();

  /// Current balance of every account: opening balance, plus income, minus
  /// expenses and transfers out, plus transfers in.
  Stream<Map<int, int>> watchBalances() => _db
      .customSelect(
        '''
        SELECT a.id AS id,
          a.opening_balance
          + COALESCE((SELECT SUM(t.amount) FROM txns t WHERE t.account_id = a.id AND t.kind = 'income'), 0)
          - COALESCE((SELECT SUM(t.amount) FROM txns t WHERE t.account_id = a.id AND t.kind IN ('expense', 'transfer')), 0)
          + COALESCE((SELECT SUM(t.amount) FROM txns t WHERE t.to_account_id = a.id AND t.kind = 'transfer'), 0)
          AS balance
        FROM accounts a
        ''',
        readsFrom: {_a, _db.txns},
      )
      .watch()
      .map((rows) => {for (final r in rows) r.read<int>('id'): r.read<int>('balance')});

  Future<int> add({
    required String name,
    required AccountType type,
    required String icon,
    required int color,
    int openingBalance = 0,
    bool includeInTotal = true,
  }) async {
    final maxOrder = _a.sortOrder.max();
    final row = await (_db.selectOnly(_a)..addColumns([maxOrder])).getSingle();
    return _db
        .into(_a)
        .insert(
          AccountsCompanion.insert(
            name: name.trim(),
            type: type,
            icon: icon,
            color: color,
            openingBalance: Value(openingBalance),
            includeInTotal: Value(includeInTotal),
            sortOrder: Value((row.read(maxOrder) ?? -1) + 1),
            createdAt: clock.now(),
          ),
        );
  }

  Future<void> save(Account a) => _db.update(_a).replace(a);

  Future<void> setArchived(int id, bool archived) => (_db.update(
    _a,
  )..where((a) => a.id.equals(id))).write(AccountsCompanion(archived: Value(archived)));

  /// Deletes the account with every transaction and rule that touches it.
  Future<void> delete(int id) => _db.transaction(() async {
    await (_db.delete(
      _db.txns,
    )..where((t) => t.accountId.equals(id) | t.toAccountId.equals(id))).go();
    await (_db.delete(
      _db.recurringRules,
    )..where((r) => r.accountId.equals(id) | r.toAccountId.equals(id))).go();
    await (_db.delete(_a)..where((a) => a.id.equals(id))).go();
  });

  Future<void> reorder(List<int> orderedIds) => _db.batch((b) {
    for (var i = 0; i < orderedIds.length; i++) {
      b.update(
        _a,
        AccountsCompanion(sortOrder: Value(i)),
        where: (a) => a.id.equals(orderedIds[i]),
      );
    }
  });
}
