import 'package:flutter_test/flutter_test.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/domain/analytics.dart';

var _id = 0;

Txn txn(TxnKind kind, int amount, DateTime date, {int? category}) => Txn(
  id: ++_id,
  kind: kind,
  amount: amount,
  categoryId: category,
  accountId: 1,
  date: date,
  note: '',
  createdAt: date,
  updatedAt: date,
);

void main() {
  const calc = PeriodCalculator();
  final october = calc.month(DateTime(2026, 10, 1));
  final september = calc.previous(october);

  group('PeriodStats', () {
    test('totals by kind and category, ignoring transfers and other periods', () {
      final stats = PeriodStats.compute(october, [
        txn(TxnKind.expense, 1000, DateTime(2026, 10, 1, 9), category: 1),
        txn(TxnKind.expense, 500, DateTime(2026, 10, 1, 18), category: 2),
        txn(TxnKind.expense, 700, DateTime(2026, 10, 3), category: 1),
        txn(TxnKind.income, 50000, DateTime(2026, 10, 1), category: 9),
        txn(TxnKind.transfer, 9999, DateTime(2026, 10, 2)),
        txn(TxnKind.expense, 123, DateTime(2026, 9, 30)),
      ]);
      expect(stats.expense, 2200);
      expect(stats.income, 50000);
      expect(stats.net, 47800);
      expect(stats.count, 5);
      expect(stats.expenseByCategory, {1: 1700, 2: 500});
      expect(stats.buckets.length, 31);
      expect(stats.buckets[0].expense, 1500);
      expect(stats.buckets[2].expense, 700);
      expect(stats.cumulativeExpense[2], 2200);
      expect(stats.largestExpense?.amount, 1000);
      expect(stats.rankedExpense().first.key, 1);
    });

    test('year view buckets by month', () {
      final year = calc.year(DateTime(2026, 5, 5));
      final stats = PeriodStats.compute(year, [
        txn(TxnKind.expense, 100, DateTime(2026, 1, 5)),
        txn(TxnKind.expense, 200, DateTime(2026, 12, 31)),
      ]);
      expect(stats.buckets.length, 12);
      expect(stats.buckets.first.expense, 100);
      expect(stats.buckets.last.expense, 200);
    });

    test('averages and projections use elapsed days', () {
      final stats = PeriodStats.compute(october, [
        txn(TxnKind.expense, 1000, DateTime(2026, 10, 2)),
      ]);
      final now = DateTime(2026, 10, 10);
      expect(stats.averagePerDay(now), 100);
      expect(stats.projectedExpense(now), 3100);
      expect(stats.noSpendDays(now), 9);
    });
  });

  group('BudgetStatus', () {
    BudgetStatus status(int limit, int spent) => BudgetStatus(
      budget: Budget(id: 1, categoryId: null, amount: limit, createdAt: DateTime(2026)),
      category: null,
      spent: spent,
      period: october,
    );

    test('levels', () {
      expect(status(1000, 500).level, BudgetLevel.ok);
      expect(status(1000, 800).level, BudgetLevel.warning);
      expect(status(1000, 1001).level, BudgetLevel.over);
    });

    test('safe to spend per remaining day', () {
      // 22 days remain from Oct 10 (inclusive).
      expect(status(31000, 9000).safePerDay(DateTime(2026, 10, 10)), 1000);
      expect(status(1000, 1200).safePerDay(DateTime(2026, 10, 10)), 0);
    });

    test('pace compares with the even share for today', () {
      // After 10 of 31 days, an even pace would be 10,000 of 31,000.
      expect(status(31000, 10000).pace(DateTime(2026, 10, 10)), closeTo(1, 0.001));
      expect(status(31000, 15000).pace(DateTime(2026, 10, 10)), closeTo(1.5, 0.001));
    });
  });

  test('insights compare with the previous period', () {
    final current = PeriodStats.compute(october, [
      txn(TxnKind.expense, 1000, DateTime(2026, 10, 1), category: 1),
      txn(TxnKind.income, 5000, DateTime(2026, 10, 1)),
    ]);
    final previous = PeriodStats.compute(september, [
      txn(TxnKind.expense, 4000, DateTime(2026, 9, 1), category: 1),
    ]);
    final insights = buildInsights(
      current: current,
      previous: previous,
      categories: const {},
      money: MoneyFormat(Currency.byCode('USD'), NumberStyle.western),
      now: DateTime(2026, 11, 2),
    );
    expect(insights.map((i) => i.title), contains('Spending down 75%'));
    expect(insights.map((i) => i.title), contains('Saved 80% of income'));
  });
}
