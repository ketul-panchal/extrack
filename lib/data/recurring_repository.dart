import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/core/time/recurrence.dart';

class RecurringRepository {
  RecurringRepository(this._db);

  final AppDatabase _db;

  $RecurringRulesTable get _r => _db.recurringRules;

  static Recurrence recurrenceOf(RecurringRule r) =>
      Recurrence(frequency: r.frequency, every: r.every, anchor: r.startDate);

  Stream<List<RecurringRule>> watchAll() => (_db.select(
    _r,
  )..orderBy([(r) => OrderingTerm.desc(r.active), (r) => OrderingTerm.asc(r.nextDue)])).watch();

  Future<List<RecurringRule>> all() => _db.select(_r).get();

  Future<RecurringRule?> byId(int id) =>
      (_db.select(_r)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<int> add({
    required TxnKind kind,
    required int amount,
    required int accountId,
    int? categoryId,
    int? toAccountId,
    String note = '',
    required Frequency frequency,
    int every = 1,
    required DateTime startDate,
    required DateTime nextDue,
    DateTime? endDate,
    bool autoPost = true,
  }) => _db
      .into(_r)
      .insert(
        RecurringRulesCompanion.insert(
          kind: kind,
          amount: amount,
          accountId: accountId,
          categoryId: Value(kind == TxnKind.transfer ? null : categoryId),
          toAccountId: Value(kind == TxnKind.transfer ? toAccountId : null),
          note: Value(note.trim()),
          frequency: frequency,
          every: Value(every < 1 ? 1 : every),
          startDate: dateOnly(startDate),
          nextDue: dateOnly(nextDue),
          endDate: Value(endDate == null ? null : dateOnly(endDate)),
          autoPost: Value(autoPost),
          createdAt: clock.now(),
        ),
      );

  Future<void> save(RecurringRule r) => _db.update(_r).replace(r);

  Future<void> delete(int id) => (_db.delete(_r)..where((r) => r.id.equals(id))).go();

  Future<void> setActive(int id, bool active) => (_db.update(
    _r,
  )..where((r) => r.id.equals(id))).write(RecurringRulesCompanion(active: Value(active)));

  /// Records the payment due on `nextDue` as paid today and moves the rule on.
  Future<int> markPaid(RecurringRule r) => _db.transaction(() async {
    final id = await _insertTxn(r, clock.now());
    await _advanceFrom(r, r.nextDue);
    return id;
  });

  /// Moves past the next occurrence without recording anything.
  Future<void> skip(RecurringRule r) => _advanceFrom(r, r.nextDue);

  Future<void> _advanceFrom(RecurringRule r, DateTime due) async {
    final next = recurrenceOf(r).after(due);
    final ended = r.endDate != null && next.isAfter(dateOnly(r.endDate!));
    await (_db.update(_r)..where((x) => x.id.equals(r.id))).write(
      RecurringRulesCompanion(nextDue: Value(next), active: Value(r.active && !ended)),
    );
  }

  /// Posts every automatic occurrence due on or before [now], catching up on
  /// days the app wasn't opened. Returns the number of transactions posted.
  Future<int> processDue(DateTime now) async {
    final today = dateOnly(now);
    final rules = await (_db.select(
      _r,
    )..where((r) => r.active & r.autoPost & r.nextDue.isSmallerOrEqualValue(today))).get();
    if (rules.isEmpty) return 0;
    var posted = 0;
    await _db.transaction(() async {
      for (final r in rules) {
        final recurrence = recurrenceOf(r);
        final end = r.endDate == null ? null : dateOnly(r.endDate!);
        var due = dateOnly(r.nextDue);
        var guard = 0;
        while (!due.isAfter(today) && (end == null || !due.isAfter(end)) && guard < 400) {
          await _insertTxn(r, DateTime(due.year, due.month, due.day, 9));
          posted++;
          guard++;
          due = recurrence.after(due);
        }
        final ended = end != null && due.isAfter(end);
        await (_db.update(_r)..where((x) => x.id.equals(r.id))).write(
          RecurringRulesCompanion(nextDue: Value(due), active: Value(!ended)),
        );
      }
    });
    return posted;
  }

  Future<int> _insertTxn(RecurringRule r, DateTime date) {
    final now = clock.now();
    return _db
        .into(_db.txns)
        .insert(
          TxnsCompanion.insert(
            kind: r.kind,
            amount: r.amount,
            accountId: r.accountId,
            toAccountId: Value(r.kind == TxnKind.transfer ? r.toAccountId : null),
            categoryId: Value(r.kind == TxnKind.transfer ? null : r.categoryId),
            date: date,
            note: Value(r.note),
            recurringId: Value(r.id),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
