import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/time/periods.dart';

/// One bar on a time chart: a day (week/month views) or a month (year view).
class Bucket {
  Bucket(this.start, this.end);

  final DateTime start;
  final DateTime end;
  int expense = 0;
  int income = 0;
}

/// Everything the dashboards need about one period, computed in one pass.
class PeriodStats {
  PeriodStats._({
    required this.period,
    required this.expense,
    required this.income,
    required this.count,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.buckets,
    required this.largestExpense,
    required this.expenseDays,
  });

  factory PeriodStats.compute(Period period, Iterable<Txn> txns) {
    final buckets = _bucketsFor(period);
    final byExpense = <int?, int>{};
    final byIncome = <int?, int>{};
    final expenseDays = <DateTime>{};
    var expense = 0;
    var income = 0;
    var count = 0;
    Txn? largest;
    for (final t in txns) {
      if (!period.contains(t.date)) continue;
      count++;
      if (t.kind == TxnKind.transfer) continue;
      final bucket = _bucketIndex(period, buckets, t.date);
      if (t.kind == TxnKind.expense) {
        expense += t.amount;
        byExpense[t.categoryId] = (byExpense[t.categoryId] ?? 0) + t.amount;
        if (bucket != null) buckets[bucket].expense += t.amount;
        expenseDays.add(dateOnly(t.date));
        if (largest == null || t.amount > largest.amount) largest = t;
      } else {
        income += t.amount;
        byIncome[t.categoryId] = (byIncome[t.categoryId] ?? 0) + t.amount;
        if (bucket != null) buckets[bucket].income += t.amount;
      }
    }
    return PeriodStats._(
      period: period,
      expense: expense,
      income: income,
      count: count,
      expenseByCategory: byExpense,
      incomeByCategory: byIncome,
      buckets: buckets,
      largestExpense: largest,
      expenseDays: expenseDays,
    );
  }

  final Period period;
  final int expense;
  final int income;

  /// Transactions of every kind in the period.
  final int count;
  final Map<int?, int> expenseByCategory;
  final Map<int?, int> incomeByCategory;
  final List<Bucket> buckets;
  final Txn? largestExpense;
  final Set<DateTime> expenseDays;

  int get net => income - expense;

  /// Share of income kept. Null without income.
  double? get savingsRate => income > 0 ? net / income : null;

  bool get isEmpty => expense == 0 && income == 0;

  /// Average spending per elapsed day.
  int averagePerDay(DateTime now) {
    final days = math.max(1, period.elapsedDays(now));
    return (expense / days).round();
  }

  /// Days with no spending so far (only counting days that have passed).
  int noSpendDays(DateTime now) {
    final elapsed = period.elapsedDays(now);
    return math.max(
      0,
      elapsed -
          expenseDays.where((d) => d.isBefore(dateOnly(now).add(const Duration(days: 1)))).length,
    );
  }

  /// Linear projection of spending at period end.
  int projectedExpense(DateTime now) {
    final elapsed = period.elapsedDays(now);
    if (elapsed <= 0) return 0;
    if (elapsed >= period.days) return expense;
    return (expense / elapsed * period.days).round();
  }

  /// Running total of spending per bucket.
  List<int> get cumulativeExpense {
    var acc = 0;
    return [for (final b in buckets) acc += b.expense];
  }

  /// Categories by spending, largest first.
  List<MapEntry<int?, int>> rankedExpense() =>
      expenseByCategory.entries.sorted((a, b) => b.value.compareTo(a.value));

  List<MapEntry<int?, int>> rankedIncome() =>
      incomeByCategory.entries.sorted((a, b) => b.value.compareTo(a.value));

  /// The day bucket with the most spending.
  Bucket? get peakBucket =>
      buckets.isEmpty ? null : buckets.reduce((a, b) => b.expense > a.expense ? b : a);

  static List<Bucket> _bucketsFor(Period p) {
    if (p.type == PeriodType.year) {
      return [
        for (var m = 0; m < 12; m++)
          Bucket(
            DateTime(p.start.year, p.start.month + m),
            DateTime(p.start.year, p.start.month + m + 1),
          ),
      ];
    }
    return [
      for (var d = 0; d < p.days; d++)
        Bucket(
          DateTime(p.start.year, p.start.month, p.start.day + d),
          DateTime(p.start.year, p.start.month, p.start.day + d + 1),
        ),
    ];
  }

  static int? _bucketIndex(Period p, List<Bucket> buckets, DateTime d) {
    if (p.type == PeriodType.year) {
      final i = (d.year - p.start.year) * 12 + d.month - p.start.month;
      return i >= 0 && i < buckets.length ? i : null;
    }
    final i = daysBetween(p.start, d);
    return i >= 0 && i < buckets.length ? i : null;
  }
}

enum BudgetLevel { ok, warning, over }

/// A budget measured against one period's spending.
class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.category,
    required this.spent,
    required this.period,
  });

  final Budget budget;

  /// Null for the overall budget.
  final Category? category;
  final int spent;
  final Period period;

  bool get isOverall => budget.categoryId == null;
  int get limit => budget.amount;
  int get remaining => limit - spent;
  double get fraction => limit <= 0 ? 0 : spent / limit;

  BudgetLevel get level {
    if (fraction > 1) return BudgetLevel.over;
    if (fraction >= 0.8) return BudgetLevel.warning;
    return BudgetLevel.ok;
  }

  /// How much can still be spent per remaining day (today included).
  int safePerDay(DateTime now) {
    final days = period.remainingDays(now);
    if (days <= 0 || remaining <= 0) return 0;
    return (remaining / days).floor();
  }

  /// >1 means spending faster than the budget allows for this point in time.
  double pace(DateTime now) {
    final elapsed = period.elapsedDays(now);
    if (elapsed <= 0 || limit <= 0) return 0;
    final expected = limit * elapsed / period.days;
    return expected <= 0 ? 0 : spent / expected;
  }

  int projected(DateTime now) {
    final elapsed = period.elapsedDays(now);
    if (elapsed <= 0) return spent;
    if (elapsed >= period.days) return spent;
    return (spent / elapsed * period.days).round();
  }
}

enum InsightTone { good, bad, neutral }

enum InsightIcon { trendDown, trendUp, calendar, star, piggy, warning, sparkle }

class Insight {
  const Insight(this.icon, this.tone, this.title, this.body);

  final InsightIcon icon;
  final InsightTone tone;
  final String title;
  final String body;
}

/// Plain-language observations about a period compared with the one before.
List<Insight> buildInsights({
  required PeriodStats current,
  required PeriodStats previous,
  required Map<int, Category> categories,
  required MoneyFormat money,
  required DateTime now,
}) {
  final out = <Insight>[];
  final prevName = PeriodCalculator.previousName(current.period.type);
  final ongoing = current.period.isCurrent(now);

  String catName(int? id) => id == null ? 'Uncategorized' : categories[id]?.name ?? 'Uncategorized';

  // 1. Pace against the same point of the previous period.
  if (current.expense > 0 && previous.expense > 0) {
    int compareTo;
    if (ongoing) {
      final idx = math.min(
        current.period.type == PeriodType.year
            ? (now.year - current.period.start.year) * 12 + now.month - current.period.start.month
            : daysBetween(current.period.start, now),
        previous.buckets.length - 1,
      );
      compareTo = idx >= 0 ? previous.cumulativeExpense[idx] : 0;
    } else {
      compareTo = previous.expense;
    }
    if (compareTo > 0) {
      final change = (current.expense - compareTo) / compareTo;
      final pct = (change.abs() * 100).round();
      final whenText = ongoing ? 'than at this point $prevName' : 'than $prevName';
      if (pct >= 5) {
        out.add(
          change < 0
              ? Insight(
                  InsightIcon.trendDown,
                  InsightTone.good,
                  'Spending down $pct%',
                  'You\'ve spent ${money.format(compareTo - current.expense)} less $whenText.',
                )
              : Insight(
                  InsightIcon.trendUp,
                  InsightTone.bad,
                  'Spending up $pct%',
                  'You\'ve spent ${money.format(current.expense - compareTo)} more $whenText.',
                ),
        );
      } else {
        out.add(
          Insight(
            InsightIcon.calendar,
            InsightTone.neutral,
            'Right on track',
            'Your spending is about the same as $prevName.',
          ),
        );
      }
    }
  }

  // 2. Biggest category movements (completed comparison only when it's fair).
  if (!ongoing || current.period.elapsedDays(now) >= current.period.days * 0.5) {
    MapEntry<int?, int>? up;
    MapEntry<int?, int>? down;
    var upDiff = 0;
    var downDiff = 0;
    final keys = {...current.expenseByCategory.keys, ...previous.expenseByCategory.keys};
    for (final k in keys) {
      final c = current.expenseByCategory[k] ?? 0;
      final p = previous.expenseByCategory[k] ?? 0;
      final diff = c - p;
      if (p > 0 && diff > upDiff && diff >= p * 0.25) {
        upDiff = diff;
        up = MapEntry(k, c);
      }
      if (p > 0 && -diff > downDiff && -diff >= p * 0.25) {
        downDiff = -diff;
        down = MapEntry(k, c);
      }
    }
    if (up != null) {
      final prev = previous.expenseByCategory[up.key]!;
      out.add(
        Insight(
          InsightIcon.trendUp,
          InsightTone.bad,
          '${catName(up.key)} is up',
          '${money.format(upDiff)} more than $prevName (${((upDiff / prev) * 100).round()}%).',
        ),
      );
    }
    if (down != null) {
      final prev = previous.expenseByCategory[down.key]!;
      out.add(
        Insight(
          InsightIcon.trendDown,
          InsightTone.good,
          'Less on ${catName(down.key)}',
          '${money.format(downDiff)} less than $prevName (${((downDiff / prev) * 100).round()}%).',
        ),
      );
    }
  }

  // 3. Savings rate.
  final rate = current.savingsRate;
  if (rate != null) {
    if (rate >= 0) {
      out.add(
        Insight(
          InsightIcon.piggy,
          rate >= 0.1 ? InsightTone.good : InsightTone.neutral,
          'Saved ${(rate * 100).round()}% of income',
          '${money.format(current.net)} left after spending ${money.format(current.expense)}.',
        ),
      );
    } else {
      out.add(
        Insight(
          InsightIcon.warning,
          InsightTone.bad,
          'Spent more than you earned',
          'Spending is ${money.format(-current.net)} above income.',
        ),
      );
    }
  }

  // 4. Weekend effect (needs enough days to mean something).
  if (current.period.type != PeriodType.week && current.expense > 0) {
    var weekend = 0, weekday = 0, weekendDays = 0, weekdayDays = 0;
    final lastIndex = ongoing ? daysBetween(current.period.start, now) : current.period.days - 1;
    if (current.period.type == PeriodType.month && lastIndex >= 13) {
      for (var i = 0; i <= lastIndex && i < current.buckets.length; i++) {
        final b = current.buckets[i];
        final isWeekend =
            b.start.weekday == DateTime.saturday || b.start.weekday == DateTime.sunday;
        if (isWeekend) {
          weekend += b.expense;
          weekendDays++;
        } else {
          weekday += b.expense;
          weekdayDays++;
        }
      }
      if (weekendDays > 0 && weekdayDays > 0 && weekday > 0) {
        final ratio = (weekend / weekendDays) / (weekday / weekdayDays);
        if (ratio >= 1.4) {
          out.add(
            Insight(
              InsightIcon.calendar,
              InsightTone.neutral,
              'Weekends cost more',
              'You spend ${ratio.toStringAsFixed(1)}× more per day on weekends.',
            ),
          );
        }
      }
    }
  }

  // 5. No-spend days.
  final noSpend = current.noSpendDays(now);
  if (current.period.type != PeriodType.year && noSpend >= 3) {
    out.add(
      Insight(
        InsightIcon.star,
        InsightTone.good,
        '$noSpend no-spend days',
        'Days without a single expense add up.',
      ),
    );
  }

  // 6. Concentration in one category.
  final ranked = current.rankedExpense();
  if (ranked.length >= 3 && current.expense > 0) {
    final top = ranked.first;
    final share = top.value / current.expense;
    if (share >= 0.35) {
      out.add(
        Insight(
          InsightIcon.sparkle,
          InsightTone.neutral,
          '${catName(top.key)} leads',
          'It makes up ${(share * 100).round()}% of your spending.',
        ),
      );
    }
  }
  return out;
}
