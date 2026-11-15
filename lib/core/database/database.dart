import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:spent/core/database/enums.dart';

export 'package:spent/core/database/enums.dart';

part 'database.g.dart';

// All money is stored as integer minor units (cents, paise…) so totals never
// drift from floating-point rounding. Amounts on transactions are positive;
// the kind decides the direction.

@DataClassName('Account')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 48)();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  BoolColumn get includeInTotal => boolean().withDefault(const Constant(true))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('Category')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get kind => textEnum<CategoryKind>()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('Txn')
@TableIndex(name: 'txns_date', columns: {#date})
@TableIndex(name: 'txns_category', columns: {#categoryId})
@TableIndex(name: 'txns_account', columns: {#accountId})
class Txns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<TxnKind>()();
  IntColumn get amount => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  @ReferenceName('outgoingTxns')
  IntColumn get accountId => integer().references(Accounts, #id, onDelete: KeyAction.cascade)();

  /// Destination account, for transfers only.
  @ReferenceName('incomingTxns')
  IntColumn get toAccountId =>
      integer().nullable().references(Accounts, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// The rule that created this transaction, if it was posted automatically.
  IntColumn get recurringId =>
      integer().nullable().references(RecurringRules, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// A monthly spending limit. A null [categoryId] is the overall budget.
@DataClassName('Budget')
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().nullable().unique().references(Categories, #id, onDelete: KeyAction.cascade)();
  IntColumn get amount => integer()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('RecurringRule')
class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<TxnKind>()();
  IntColumn get amount => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  @ReferenceName('outgoingRules')
  IntColumn get accountId => integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('incomingRules')
  IntColumn get toAccountId =>
      integer().nullable().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get frequency => textEnum<Frequency>()();

  /// Repeat every N [frequency] units.
  IntColumn get every => integer().withDefault(const Constant(1))();

  /// First occurrence. Its day-of-month anchors monthly rules (31st → last day).
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get nextDue => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// Post automatically when due; otherwise it waits in "Due" for a tap.
  BoolColumn get autoPost => boolean().withDefault(const Constant(true))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('Goal')
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  IntColumn get target => integer()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Money put toward (positive) or taken out of (negative) a goal.
@DataClassName('GoalEntry')
class GoalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get goalId => integer().references(Goals, #id, onDelete: KeyAction.cascade)();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

@DriftDatabase(tables: [Accounts, Categories, Txns, Budgets, RecurringRules, Goals, GoalEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: 'spent');

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Deletes every row, children first. Used by restore and "erase all data".
  Future<void> wipe() => transaction(() async {
    await delete(goalEntries).go();
    await delete(goals).go();
    await delete(txns).go();
    await delete(budgets).go();
    await delete(recurringRules).go();
    await delete(categories).go();
    await delete(accounts).go();
  });
}
