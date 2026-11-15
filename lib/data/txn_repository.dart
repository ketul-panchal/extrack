import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/data/models.dart';

class TxnRepository {
  TxnRepository(this._db);

  final AppDatabase _db;

  $TxnsTable get _t => _db.txns;

  /// Transactions dated in [from, to), newest first.
  Stream<List<Txn>> watchRange(DateTime from, DateTime to) {
    final q = _db.select(_t)
      ..where((t) => t.date.isBiggerOrEqualValue(from) & t.date.isSmallerThanValue(to))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]);
    return q.watch();
  }

  Stream<List<Txn>> watchRecent({int limit = 30}) {
    final q = _db.select(_t)
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    return q.watch();
  }

  /// Everything that moved money in or out of an account.
  Stream<List<Txn>> watchForAccount(int accountId, {int limit = 300}) {
    final q = _db.select(_t)
      ..where((t) => t.accountId.equals(accountId) | t.toAccountId.equals(accountId))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    return q.watch();
  }

  /// Everything recorded by a recurring rule, newest first.
  Stream<List<Txn>> watchForRecurring(int recurringId, {int limit = 300}) {
    final q = _db.select(_t)
      ..where((t) => t.recurringId.equals(recurringId))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    return q.watch();
  }

  Stream<List<Txn>> watchForCategory(int categoryId, DateTime from, DateTime to) {
    final q = _db.select(_t)
      ..where(
        (t) =>
            t.categoryId.equals(categoryId) &
            t.date.isBiggerOrEqualValue(from) &
            t.date.isSmallerThanValue(to),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]);
    return q.watch();
  }

  Stream<Txn?> watchOne(int id) =>
      (_db.select(_t)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Txn?> byId(int id) => (_db.select(_t)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> add({
    required TxnKind kind,
    required int amount,
    required int accountId,
    required DateTime date,
    int? categoryId,
    int? toAccountId,
    String note = '',
    int? recurringId,
  }) {
    final now = clock.now();
    return _db
        .into(_t)
        .insert(
          TxnsCompanion.insert(
            kind: kind,
            amount: amount,
            accountId: accountId,
            date: date,
            categoryId: Value(kind == TxnKind.transfer ? null : categoryId),
            toAccountId: Value(kind == TxnKind.transfer ? toAccountId : null),
            note: Value(note.trim()),
            recurringId: Value(recurringId),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> save(Txn txn) => _db.update(_t).replace(txn.copyWith(updatedAt: clock.now()));

  Future<void> delete(int id) => (_db.delete(_t)..where((t) => t.id.equals(id))).go();

  /// Puts a deleted transaction back exactly as it was (undo).
  Future<void> restore(Txn txn) => _db.into(_t).insert(txn, mode: InsertMode.insertOrReplace);

  Future<void> restoreAll(List<Txn> txns) => _db.batch((b) {
    b.insertAll(_t, txns, mode: InsertMode.insertOrReplace);
  });

  Future<void> deleteMany(Iterable<int> ids) => (_db.delete(_t)..where((t) => t.id.isIn(ids))).go();

  /// Full search used by the Search screen, kept live as data changes.
  Stream<List<Txn>> watchSearch(
    TxnFilter f, {
    Set<int> categoryIdsMatchingQuery = const {},
    Set<int> accountIdsMatchingQuery = const {},
    int? amountMatchingQuery,
    int limit = 400,
  }) => _searchQuery(
    f,
    categoryIdsMatchingQuery: categoryIdsMatchingQuery,
    accountIdsMatchingQuery: accountIdsMatchingQuery,
    amountMatchingQuery: amountMatchingQuery,
    limit: limit,
  ).watch();

  Future<List<Txn>> search(TxnFilter f, {int limit = 400}) => _searchQuery(f, limit: limit).get();

  SimpleSelectStatement<$TxnsTable, Txn> _searchQuery(
    TxnFilter f, {
    Set<int> categoryIdsMatchingQuery = const {},
    Set<int> accountIdsMatchingQuery = const {},
    int? amountMatchingQuery,
    int limit = 400,
  }) {
    final q = _db.select(_t);
    q.where((t) {
      Expression<bool> e = const Constant(true);
      final text = f.query.trim();
      if (text.isNotEmpty) {
        final escaped = text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
        Expression<bool> match = t.note.like('%$escaped%', escapeChar: r'\');
        if (categoryIdsMatchingQuery.isNotEmpty) {
          match = match | t.categoryId.isIn(categoryIdsMatchingQuery);
        }
        if (accountIdsMatchingQuery.isNotEmpty) {
          match =
              match |
              t.accountId.isIn(accountIdsMatchingQuery) |
              t.toAccountId.isIn(accountIdsMatchingQuery);
        }
        if (amountMatchingQuery != null) match = match | t.amount.equals(amountMatchingQuery);
        e = e & match;
      }
      if (f.kinds.isNotEmpty) e = e & t.kind.isInValues(f.kinds);
      if (f.categoryIds.isNotEmpty) e = e & t.categoryId.isIn(f.categoryIds);
      if (f.accountIds.isNotEmpty) {
        e = e & (t.accountId.isIn(f.accountIds) | t.toAccountId.isIn(f.accountIds));
      }
      if (f.from != null) e = e & t.date.isBiggerOrEqualValue(f.from!);
      if (f.to != null) e = e & t.date.isSmallerThanValue(f.to!);
      if (f.minAmount != null) e = e & t.amount.isBiggerOrEqualValue(f.minAmount!);
      if (f.maxAmount != null) e = e & t.amount.isSmallerOrEqualValue(f.maxAmount!);
      return e;
    });
    q.orderBy(switch (f.sort) {
      TxnSort.newest => [(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)],
      TxnSort.oldest => [(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)],
      TxnSort.largest => [(t) => OrderingTerm.desc(t.amount), (t) => OrderingTerm.desc(t.date)],
      TxnSort.smallest => [(t) => OrderingTerm.asc(t.amount), (t) => OrderingTerm.desc(t.date)],
    });
    q.limit(limit);
    return q;
  }

  /// Notes used before that start with [prefix], most used first, each with
  /// its usual category and most recent amount.
  Future<List<NoteSuggestion>> suggestions(TxnKind kind, String prefix, {int limit = 6}) async {
    final text = prefix.trim();
    if (text.isEmpty) return const [];
    final escaped = text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    // SQLite takes bare columns (amount) from the row holding MAX(date).
    final rows = await _db
        .customSelect(
          r'''
          SELECT note, category_id, amount, COUNT(*) AS uses, MAX(date) AS last_used
          FROM txns
          WHERE kind = ? AND note <> '' AND note LIKE ? ESCAPE '\'
          GROUP BY lower(note), category_id
          ORDER BY uses DESC, last_used DESC
          LIMIT ?
          ''',
          variables: [
            Variable.withString(kind.name),
            Variable.withString('$escaped%'),
            Variable.withInt(limit),
          ],
          readsFrom: {_t},
        )
        .get();
    final seen = <String>{};
    final out = <NoteSuggestion>[];
    for (final r in rows) {
      final note = r.read<String>('note');
      if (!seen.add(note.toLowerCase())) continue;
      out.add(
        NoteSuggestion(
          note: note,
          categoryId: r.readNullable<int>('category_id'),
          lastAmount: r.read<int>('amount'),
          uses: r.read<int>('uses'),
        ),
      );
    }
    return out;
  }

  /// How often each category was used recently, for ordering pickers.
  Future<Map<int, int>> categoryUsage(
    TxnKind kind, {
    Duration window = const Duration(days: 120),
  }) async {
    final since = clock.now().subtract(window);
    final count = _t.id.count();
    final q = _db.selectOnly(_t)
      ..addColumns([_t.categoryId, count])
      ..where(
        _t.kind.equalsValue(kind) & _t.categoryId.isNotNull() & _t.date.isBiggerOrEqualValue(since),
      )
      ..groupBy([_t.categoryId]);
    final rows = await q.get();
    return {for (final r in rows) r.read(_t.categoryId)!: r.read(count) ?? 0};
  }

  Future<int> countForCategory(int categoryId) async {
    final count = _t.id.count();
    final q = _db.selectOnly(_t)
      ..addColumns([count])
      ..where(_t.categoryId.equals(categoryId));
    return (await q.getSingle()).read(count) ?? 0;
  }

  Future<int> countForAccount(int accountId) async {
    final count = _t.id.count();
    final q = _db.selectOnly(_t)
      ..addColumns([count])
      ..where(_t.accountId.equals(accountId) | _t.toAccountId.equals(accountId));
    return (await q.getSingle()).read(count) ?? 0;
  }

  Future<int> countAll() async {
    final count = _t.id.count();
    final q = _db.selectOnly(_t)..addColumns([count]);
    return (await q.getSingle()).read(count) ?? 0;
  }

  Stream<int> watchCount() {
    final count = _t.id.count();
    final q = _db.selectOnly(_t)..addColumns([count]);
    return q.watchSingle().map((r) => r.read(count) ?? 0);
  }

  Future<DateTime?> firstDate() async {
    final min = _t.date.min();
    final q = _db.selectOnly(_t)..addColumns([min]);
    return (await q.getSingle()).read(min);
  }

  Future<List<Txn>> all() => (_db.select(
    _t,
  )..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)])).get();

  Future<List<Txn>> inRange(DateTime from, DateTime to) =>
      (_db.select(_t)
            ..where((t) => t.date.isBiggerOrEqualValue(from) & t.date.isSmallerThanValue(to))
            ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
          .get();
}
