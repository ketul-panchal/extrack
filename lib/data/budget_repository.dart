import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:spent/core/database/database.dart';

class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  $BudgetsTable get _b => _db.budgets;

  Stream<List<Budget>> watchAll() =>
      (_db.select(_b)..orderBy([(b) => OrderingTerm.asc(b.id)])).watch();

  Future<List<Budget>> all() => _db.select(_b).get();

  /// Sets the monthly limit for [categoryId] (null = overall budget).
  /// A null or zero [amount] removes it.
  Future<void> set(int? categoryId, int? amount) => _db.transaction(() async {
    final existing =
        await (_db.select(_b)..where(
              (b) => categoryId == null ? b.categoryId.isNull() : b.categoryId.equals(categoryId),
            ))
            .get();
    if (amount == null || amount <= 0) {
      for (final row in existing) {
        await (_db.delete(_b)..where((b) => b.id.equals(row.id))).go();
      }
      return;
    }
    if (existing.isEmpty) {
      await _db
          .into(_b)
          .insert(
            BudgetsCompanion.insert(
              categoryId: Value(categoryId),
              amount: amount,
              createdAt: clock.now(),
            ),
          );
    } else {
      await (_db.update(_b)..where((b) => b.id.equals(existing.first.id))).write(
        BudgetsCompanion(amount: Value(amount)),
      );
      // Keep one overall budget even if an older version wrote duplicates.
      for (final dup in existing.skip(1)) {
        await (_db.delete(_b)..where((b) => b.id.equals(dup.id))).go();
      }
    }
  });
}
