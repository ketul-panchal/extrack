import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/services/backup_service.dart';
import 'package:spent/core/services/sample_data.dart';
import 'package:spent/data/account_repository.dart';
import 'package:spent/data/budget_repository.dart';
import 'package:spent/data/category_repository.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/recurring_repository.dart';
import 'package:spent/data/txn_repository.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late CategoryRepository categories;
  late TxnRepository txns;
  late RecurringRepository recurring;

  setUp(() async {
    db = memoryDatabase();
    accounts = AccountRepository(db);
    categories = CategoryRepository(db);
    txns = TxnRepository(db);
    recurring = RecurringRepository(db);
    await categories.seedDefaults();
  });

  tearDown(() => db.close());

  Future<int> category(String name) async =>
      (await categories.all()).firstWhere((c) => c.name == name).id;

  test('seeds default categories once', () async {
    final first = await categories.all();
    await categories.seedDefaults();
    expect((await categories.all()).length, first.length);
    expect(first.where((c) => c.kind == CategoryKind.income), isNotEmpty);
  });

  test('balances add income, subtract spending and move transfers', () async {
    final bank = await accounts.add(
      name: 'Bank',
      type: AccountType.bank,
      icon: 'bank',
      color: 0,
      openingBalance: 10000,
    );
    final cash = await accounts.add(
      name: 'Cash',
      type: AccountType.cash,
      icon: 'cash',
      color: 0,
      openingBalance: 500,
    );
    final food = await category('Food & Dining');
    final salary = await category('Salary');
    final now = DateTime(2026, 10, 8);
    await txns.add(
      kind: TxnKind.income,
      amount: 50000,
      accountId: bank,
      categoryId: salary,
      date: now,
    );
    await txns.add(
      kind: TxnKind.expense,
      amount: 1200,
      accountId: bank,
      categoryId: food,
      date: now,
    );
    await txns.add(
      kind: TxnKind.transfer,
      amount: 3000,
      accountId: bank,
      toAccountId: cash,
      date: now,
    );
    await txns.add(
      kind: TxnKind.expense,
      amount: 250,
      accountId: cash,
      categoryId: food,
      date: now,
    );

    final balances = await accounts.watchBalances().first;
    expect(balances[bank], 10000 + 50000 - 1200 - 3000);
    expect(balances[cash], 500 + 3000 - 250);
  });

  test('transfers never carry a category', () async {
    final a = await accounts.add(name: 'A', type: AccountType.bank, icon: 'bank', color: 0);
    final b = await accounts.add(name: 'B', type: AccountType.cash, icon: 'cash', color: 0);
    final id = await txns.add(
      kind: TxnKind.transfer,
      amount: 100,
      accountId: a,
      toAccountId: b,
      categoryId: await category('Food & Dining'),
      date: DateTime(2026, 10, 8),
    );
    expect((await txns.byId(id))!.categoryId, isNull);
  });

  test('recurring rules catch up on missed months and clamp month ends', () async {
    final bank = await accounts.add(name: 'Bank', type: AccountType.bank, icon: 'bank', color: 0);
    final rent = await category('Housing');
    final id = await recurring.add(
      kind: TxnKind.expense,
      amount: 30000,
      accountId: bank,
      categoryId: rent,
      note: 'Rent',
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 31),
      nextDue: DateTime(2026, 7, 31),
    );
    expect(await recurring.processDue(DateTime(2026, 10, 8, 12)), 3);
    final posted = await txns.all();
    expect(posted.map((t) => DateTime(t.date.year, t.date.month, t.date.day)), [
      DateTime(2026, 7, 31),
      DateTime(2026, 8, 31),
      DateTime(2026, 9, 30),
    ]);
    expect(posted.every((t) => t.recurringId == id && t.note == 'Rent'), isTrue);
    expect((await recurring.byId(id))!.nextDue, DateTime(2026, 10, 31));
    // Running again posts nothing new.
    expect(await recurring.processDue(DateTime(2026, 10, 8, 18)), 0);
  });

  test('manual rules wait to be paid; end dates stop rules', () async {
    final bank = await accounts.add(name: 'Bank', type: AccountType.bank, icon: 'bank', color: 0);
    final manual = await recurring.add(
      kind: TxnKind.expense,
      amount: 999,
      accountId: bank,
      categoryId: await category('Bills & Utilities'),
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 10, 1),
      nextDue: DateTime(2026, 10, 1),
      autoPost: false,
    );
    final ending = await recurring.add(
      kind: TxnKind.expense,
      amount: 100,
      accountId: bank,
      categoryId: await category('Subscriptions'),
      frequency: Frequency.weekly,
      startDate: DateTime(2026, 9, 1),
      nextDue: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 10),
    );
    expect(await recurring.processDue(DateTime(2026, 10, 8)), 2);
    expect((await recurring.byId(ending))!.active, isFalse);

    final rule = (await recurring.byId(manual))!;
    expect(rule.nextDue, DateTime(2026, 10, 1));
    await recurring.markPaid(rule);
    expect((await recurring.byId(manual))!.nextDue, DateTime(2026, 11, 1));
    await recurring.skip((await recurring.byId(manual))!);
    expect((await recurring.byId(manual))!.nextDue, DateTime(2026, 12, 1));
    expect((await txns.all()).where((t) => t.recurringId == manual).length, 1);
  });

  test('deleting a category moves its transactions and budget goes away', () async {
    final bank = await accounts.add(name: 'Bank', type: AccountType.bank, icon: 'bank', color: 0);
    final coffee = await categories.add(
      name: 'Coffee',
      kind: CategoryKind.expense,
      icon: 'coffee',
      color: 0,
    );
    final food = await category('Food & Dining');
    await BudgetRepository(db).set(coffee, 5000);
    final id = await txns.add(
      kind: TxnKind.expense,
      amount: 300,
      accountId: bank,
      categoryId: coffee,
      date: DateTime(2026, 10, 8),
    );
    await categories.delete(coffee, moveTo: food);
    expect((await txns.byId(id))!.categoryId, food);
    expect(await BudgetRepository(db).all(), isEmpty);
  });

  test('overall budget is unique and removable', () async {
    final budgets = BudgetRepository(db);
    await budgets.set(null, 1000);
    await budgets.set(null, 2000);
    var all = await budgets.all();
    expect(all.length, 1);
    expect(all.single.amount, 2000);
    await budgets.set(null, null);
    all = await budgets.all();
    expect(all, isEmpty);
  });

  test('search matches notes, category names, amounts and filters', () async {
    final bank = await accounts.add(name: 'Bank', type: AccountType.bank, icon: 'bank', color: 0);
    final food = await category('Food & Dining');
    final transport = await category('Transport');
    final d = DateTime(2026, 10, 8);
    await txns.add(
      kind: TxnKind.expense,
      amount: 450,
      accountId: bank,
      categoryId: food,
      note: 'Pizza night',
      date: d,
    );
    await txns.add(
      kind: TxnKind.expense,
      amount: 1200,
      accountId: bank,
      categoryId: transport,
      note: 'Fuel',
      date: d,
    );
    await txns.add(
      kind: TxnKind.expense,
      amount: 999,
      accountId: bank,
      categoryId: food,
      note: '100% juice',
      date: d,
    );

    Future<List<String>> notes(TxnFilter f, {Set<int> cats = const {}, int? amount}) async => [
      for (final t
          in await txns
              .watchSearch(f, categoryIdsMatchingQuery: cats, amountMatchingQuery: amount)
              .first)
        t.note,
    ];

    expect(await notes(const TxnFilter(query: 'pizza')), ['Pizza night']);
    expect(await notes(const TxnFilter(query: 'transport'), cats: {transport}), ['Fuel']);
    expect(await notes(const TxnFilter(query: '12'), amount: 1200), ['Fuel']);
    // LIKE wildcards in the query are matched literally.
    expect(await notes(const TxnFilter(query: '100%')), ['100% juice']);
    expect(await notes(TxnFilter(categoryIds: {food}, sort: TxnSort.largest)), [
      '100% juice',
      'Pizza night',
    ]);
    expect(await notes(const TxnFilter(minAmount: 1000)), ['Fuel']);
  });

  test('note suggestions remember the usual category and last amount', () async {
    final bank = await accounts.add(name: 'Bank', type: AccountType.bank, icon: 'bank', color: 0);
    final food = await category('Food & Dining');
    await txns.add(
      kind: TxnKind.expense,
      amount: 180,
      accountId: bank,
      categoryId: food,
      note: 'Coffee',
      date: DateTime(2026, 10, 1),
    );
    await txns.add(
      kind: TxnKind.expense,
      amount: 220,
      accountId: bank,
      categoryId: food,
      note: 'Coffee',
      date: DateTime(2026, 10, 5),
    );
    final s = await txns.suggestions(TxnKind.expense, 'cof');
    expect(s.single.note, 'Coffee');
    expect(s.single.categoryId, food);
    expect(s.single.lastAmount, 220);
    expect(s.single.uses, 2);
  });

  test('backup restores every table exactly', () async {
    await SampleData(db, Currency.byCode('INR')).load();
    final service = BackupService(db);
    final bytes = await service.exportBytes(settings: const {'currencyCode': 'INR'});
    final before = await AccountRepository(db).watchBalances().first;
    final beforeCount = await txns.countAll();
    expect(beforeCount, greaterThan(100));

    final other = memoryDatabase();
    addTearDown(other.close);
    final restoreService = BackupService(other);
    final json = restoreService.decode(bytes);
    final summary = restoreService.summarize(json);
    expect(summary.transactions, beforeCount);
    await restoreService.restore(json);

    expect(await TxnRepository(other).countAll(), beforeCount);
    expect(await AccountRepository(other).watchBalances().first, before);
    expect(
      (await other.select(other.goalEntries).get()).length,
      (await db.select(db.goalEntries).get()).length,
    );

    final csv = utf8.decode(
      await restoreService.csv(MoneyFormat(Currency.byCode('INR'), NumberStyle.indian)),
    );
    expect(csv.split('\n').first, contains('Date,Type,Amount,Currency,Category'));
  });

  test('restore rejects files that are not backups', () {
    final service = BackupService(db);
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
    expect(() => service.decode(bytes('hello')), throwsA(isA<BackupException>()));
    expect(() => service.decode(bytes('{"format":"other"}')), throwsA(isA<BackupException>()));
  });
}
