import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/data/models.dart';

class GoalRepository {
  GoalRepository(this._db);

  final AppDatabase _db;

  $GoalsTable get _g => _db.goals;
  $GoalEntriesTable get _e => _db.goalEntries;

  /// Goals with their saved totals: active first, then completed, then archived.
  Stream<List<GoalProgress>> watchAll() => _db
      .customSelect(
        '''
        SELECT g.*, COALESCE(SUM(e.amount), 0) AS saved, COUNT(e.id) AS entry_count
        FROM goals g
        LEFT JOIN goal_entries e ON e.goal_id = g.id
        GROUP BY g.id
        ORDER BY g.archived ASC, (g.completed_at IS NOT NULL) ASC, g.created_at ASC
        ''',
        readsFrom: {_g, _e},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            GoalProgress(_g.map(r.data), r.read<int>('saved'), r.read<int>('entry_count')),
        ],
      );

  Stream<List<GoalEntry>> watchEntries(int goalId) =>
      (_db.select(_e)
            ..where((e) => e.goalId.equals(goalId))
            ..orderBy([(e) => OrderingTerm.desc(e.date), (e) => OrderingTerm.desc(e.id)]))
          .watch();

  Future<int> add({
    required String name,
    required int target,
    required String icon,
    required int color,
    DateTime? deadline,
  }) => _db
      .into(_g)
      .insert(
        GoalsCompanion.insert(
          name: name.trim(),
          target: target,
          icon: icon,
          color: color,
          deadline: Value(deadline),
          createdAt: clock.now(),
        ),
      );

  Future<void> save(Goal g) => _db.update(_g).replace(g);

  Future<void> delete(int id) => _db.transaction(() async {
    await (_db.delete(_e)..where((e) => e.goalId.equals(id))).go();
    await (_db.delete(_g)..where((g) => g.id.equals(id))).go();
  });

  Future<void> addEntry(int goalId, int amount, {DateTime? date, String note = ''}) => _db
      .into(_e)
      .insert(
        GoalEntriesCompanion.insert(
          goalId: goalId,
          amount: amount,
          date: date ?? clock.now(),
          note: Value(note.trim()),
        ),
      );

  Future<void> deleteEntry(int id) => (_db.delete(_e)..where((e) => e.id.equals(id))).go();

  Future<void> setCompleted(int id, DateTime? at) =>
      (_db.update(_g)..where((g) => g.id.equals(id))).write(GoalsCompanion(completedAt: Value(at)));

  Future<void> setArchived(int id, bool archived) => (_db.update(
    _g,
  )..where((g) => g.id.equals(id))).write(GoalsCompanion(archived: Value(archived)));

  Future<int> savedFor(int goalId) async {
    final sum = _e.amount.sum();
    final row =
        await (_db.selectOnly(_e)
              ..addColumns([sum])
              ..where(_e.goalId.equals(goalId)))
            .getSingle();
    return row.read(sum) ?? 0;
  }
}
