import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/theme/palette.dart';

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  $CategoriesTable get _c => _db.categories;

  Stream<List<Category>> watchAll() => (_db.select(
    _c,
  )..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)])).watch();

  Future<List<Category>> all() => (_db.select(
    _c,
  )..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)])).get();

  Future<int> add({
    required String name,
    required CategoryKind kind,
    required String icon,
    required int color,
  }) async {
    final maxOrder = _c.sortOrder.max();
    final row =
        await (_db.selectOnly(_c)
              ..addColumns([maxOrder])
              ..where(_c.kind.equalsValue(kind)))
            .getSingle();
    return _db
        .into(_c)
        .insert(
          CategoriesCompanion.insert(
            name: name.trim(),
            kind: kind,
            icon: icon,
            color: color,
            sortOrder: Value((row.read(maxOrder) ?? -1) + 1),
            createdAt: clock.now(),
          ),
        );
  }

  Future<void> save(Category c) => _db.update(_c).replace(c);

  Future<void> setArchived(int id, bool archived) => (_db.update(
    _c,
  )..where((c) => c.id.equals(id))).write(CategoriesCompanion(archived: Value(archived)));

  Future<void> reorder(List<int> orderedIds) => _db.batch((b) {
    for (var i = 0; i < orderedIds.length; i++) {
      b.update(
        _c,
        CategoriesCompanion(sortOrder: Value(i)),
        where: (c) => c.id.equals(orderedIds[i]),
      );
    }
  });

  /// Deletes a category, first moving its transactions and rules to
  /// [moveTo] (or leaving them uncategorized when null).
  Future<void> delete(int id, {int? moveTo}) => _db.transaction(() async {
    await (_db.update(
      _db.txns,
    )..where((t) => t.categoryId.equals(id))).write(TxnsCompanion(categoryId: Value(moveTo)));
    await (_db.update(_db.recurringRules)..where((r) => r.categoryId.equals(id))).write(
      RecurringRulesCompanion(categoryId: Value(moveTo)),
    );
    await (_db.delete(_db.budgets)..where((b) => b.categoryId.equals(id))).go();
    await (_db.delete(_c)..where((c) => c.id.equals(id))).go();
  });

  /// Creates the starter set on first run.
  Future<void> seedDefaults() async {
    final existing = await all();
    if (existing.isNotEmpty) return;
    final now = clock.now();
    await _db.batch((b) {
      var order = 0;
      for (final (name, icon, color) in defaultExpenseCategories) {
        b.insert(
          _c,
          CategoriesCompanion.insert(
            name: name,
            kind: CategoryKind.expense,
            icon: icon,
            color: color.light.toARGB32(),
            sortOrder: Value(order++),
            createdAt: now,
          ),
        );
      }
      order = 0;
      for (final (name, icon, color) in defaultIncomeCategories) {
        b.insert(
          _c,
          CategoriesCompanion.insert(
            name: name,
            kind: CategoryKind.income,
            icon: icon,
            color: color.light.toARGB32(),
            sortOrder: Value(order++),
            createdAt: now,
          ),
        );
      }
    });
  }

  static const defaultExpenseCategories = <(String, String, EntityColor)>[
    ('Food & Dining', 'food', EntityColors.orange),
    ('Groceries', 'groceries', EntityColors.green),
    ('Transport', 'car', EntityColors.blue),
    ('Shopping', 'shopping', EntityColors.magenta),
    ('Bills & Utilities', 'bolt', EntityColors.yellow),
    ('Housing', 'home', EntityColors.violet),
    ('Health', 'health', EntityColors.red),
    ('Entertainment', 'movie', EntityColors.aqua),
    ('Travel', 'flight', EntityColors.teal),
    ('Education', 'school', EntityColors.indigo),
    ('Personal Care', 'spa', EntityColors.rose),
    ('Subscriptions', 'subscriptions', EntityColors.lime),
    ('Gifts & Donations', 'gift', EntityColors.magenta),
    ('Other', 'other', EntityColors.slate),
  ];

  static const defaultIncomeCategories = <(String, String, EntityColor)>[
    ('Salary', 'salary', EntityColors.green),
    ('Business', 'business', EntityColors.blue),
    ('Freelance', 'laptop', EntityColors.indigo),
    ('Investments', 'chart', EntityColors.aqua),
    ('Gifts', 'gift', EntityColors.magenta),
    ('Refunds', 'refund', EntityColors.teal),
    ('Other income', 'coin', EntityColors.slate),
  ];
}
