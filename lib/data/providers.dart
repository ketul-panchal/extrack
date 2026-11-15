import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/account_repository.dart';
import 'package:spent/data/budget_repository.dart';
import 'package:spent/data/category_repository.dart';
import 'package:spent/data/goal_repository.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/recurring_repository.dart';
import 'package:spent/data/txn_repository.dart';
import 'package:spent/domain/analytics.dart';

// ── Database & repositories ────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final txnRepositoryProvider = Provider((ref) => TxnRepository(ref.watch(databaseProvider)));
final accountRepositoryProvider = Provider((ref) => AccountRepository(ref.watch(databaseProvider)));
final categoryRepositoryProvider = Provider(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);
final budgetRepositoryProvider = Provider((ref) => BudgetRepository(ref.watch(databaseProvider)));
final recurringRepositoryProvider = Provider(
  (ref) => RecurringRepository(ref.watch(databaseProvider)),
);
final goalRepositoryProvider = Provider((ref) => GoalRepository(ref.watch(databaseProvider)));

// ── Time ───────────────────────────────────────────────────────────────────

/// Today's date, updated at midnight while the app is open.
final todayProvider = NotifierProvider<TodayNotifier, DateTime>(TodayNotifier.new);

class TodayNotifier extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    _schedule();
    return dateOnly(clock.now());
  }

  void _schedule() {
    _timer?.cancel();
    final now = clock.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(midnight.difference(now) + const Duration(seconds: 1), () {
      refresh();
      _schedule();
    });
  }

  /// Call on app resume; the timer doesn't run while suspended.
  void refresh() {
    final today = dateOnly(clock.now());
    if (today != state) state = today;
  }
}

/// The budget cycle containing today.
final currentMonthProvider = Provider<Period>(
  (ref) => ref.watch(periodCalculatorProvider).month(ref.watch(todayProvider)),
);

// ── Reference data ─────────────────────────────────────────────────────────

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAll(),
);

final accountMapProvider = Provider<Map<int, Account>>(
  (ref) => {for (final a in ref.watch(accountsProvider).value ?? const <Account>[]) a.id: a},
);

final activeAccountsProvider = Provider<List<Account>>(
  (ref) => [
    for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
      if (!a.archived) a,
  ],
);

final balancesProvider = StreamProvider<Map<int, int>>(
  (ref) => ref.watch(accountRepositoryProvider).watchBalances(),
);

/// Sum of balances of accounts counted in the total.
final netWorthProvider = Provider<int>((ref) {
  final balances = ref.watch(balancesProvider).value ?? const <int, int>{};
  var total = 0;
  for (final a in ref.watch(activeAccountsProvider)) {
    if (a.includeInTotal) total += balances[a.id] ?? a.openingBalance;
  }
  return total;
});

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);

final categoryMapProvider = Provider<Map<int, Category>>(
  (ref) => {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c},
);

/// Active (non-archived) categories of one kind, in the user's order.
final categoriesOfKindProvider = Provider.family<List<Category>, CategoryKind>(
  (ref, kind) => [
    for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
      if (c.kind == kind && !c.archived) c,
  ],
);

final budgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchAll(),
);

final recurringProvider = StreamProvider<List<RecurringRule>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchAll(),
);

final goalsProvider = StreamProvider<List<GoalProgress>>(
  (ref) => ref.watch(goalRepositoryProvider).watchAll(),
);

final goalEntriesProvider = StreamProvider.autoDispose.family<List<GoalEntry>, int>(
  (ref, goalId) => ref.watch(goalRepositoryProvider).watchEntries(goalId),
);

final txnCountProvider = StreamProvider<int>(
  (ref) => ref.watch(txnRepositoryProvider).watchCount(),
);

/// Live search results. The query also matches category and account names
/// and, when it looks like a number, exact amounts.
final searchResultsProvider = StreamProvider.autoDispose.family<List<Txn>, TxnFilter>((ref, f) {
  if (f.isEmpty) return Stream.value(const <Txn>[]);
  final text = f.query.trim().toLowerCase();
  final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
  final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
  final money = ref.watch(moneyFormatProvider);
  return ref
      .watch(txnRepositoryProvider)
      .watchSearch(
        f,
        categoryIdsMatchingQuery: text.isEmpty
            ? const {}
            : {
                for (final c in categories)
                  if (c.name.toLowerCase().contains(text)) c.id,
              },
        accountIdsMatchingQuery: text.isEmpty
            ? const {}
            : {
                for (final a in accounts)
                  if (a.name.toLowerCase().contains(text)) a.id,
              },
        amountMatchingQuery: RegExp(r'^[\d.,]+$').hasMatch(text) ? money.parse(text) : null,
      );
});

// ── Transactions ───────────────────────────────────────────────────────────

final txnsInPeriodProvider = StreamProvider.autoDispose.family<List<Txn>, Period>(
  (ref, p) => ref.watch(txnRepositoryProvider).watchRange(p.start, p.end),
);

final txnViewsInPeriodProvider = Provider.autoDispose.family<AsyncValue<List<TxnView>>, Period>((
  ref,
  p,
) {
  final categories = ref.watch(categoryMapProvider);
  final accounts = ref.watch(accountMapProvider);
  return ref.watch(txnsInPeriodProvider(p)).whenData((t) => TxnView.build(t, categories, accounts));
});

final recentTxnViewsProvider = StreamProvider<List<TxnView>>((ref) {
  final categories = ref.watch(categoryMapProvider);
  final accounts = ref.watch(accountMapProvider);
  return ref
      .watch(txnRepositoryProvider)
      .watchRecent(limit: 8)
      .map((t) => TxnView.build(t, categories, accounts));
});

/// One category's transactions in [from, to).
final categoryTxnsProvider = StreamProvider.autoDispose
    .family<List<Txn>, (int, DateTime, DateTime)>(
      (ref, a) => ref.watch(txnRepositoryProvider).watchForCategory(a.$1, a.$2, a.$3),
    );

/// Everything that touched one account, newest first.
final accountTxnsProvider = StreamProvider.autoDispose.family<List<Txn>, int>(
  (ref, id) => ref.watch(txnRepositoryProvider).watchForAccount(id),
);

/// Everything recorded by one recurring rule, newest first.
final recurringTxnsProvider = StreamProvider.autoDispose.family<List<Txn>, int>(
  (ref, id) => ref.watch(txnRepositoryProvider).watchForRecurring(id),
);

final periodStatsProvider = Provider.autoDispose.family<AsyncValue<PeriodStats>, Period>(
  (ref, p) => ref.watch(txnsInPeriodProvider(p)).whenData((t) => PeriodStats.compute(p, t)),
);

/// Every budget measured against [period], overall first then by usage.
final budgetStatusesProvider = Provider.autoDispose.family<AsyncValue<List<BudgetStatus>>, Period>((
  ref,
  p,
) {
  final budgets = ref.watch(budgetsProvider);
  final stats = ref.watch(periodStatsProvider(p));
  final categories = ref.watch(categoryMapProvider);
  if (budgets is AsyncError) return AsyncError(budgets.error!, budgets.stackTrace!);
  if (stats is AsyncError) return AsyncError(stats.error!, stats.stackTrace!);
  final b = budgets.value;
  final s = stats.value;
  if (b == null || s == null) return const AsyncLoading();
  final out = <BudgetStatus>[];
  for (final budget in b) {
    final cat = budget.categoryId == null ? null : categories[budget.categoryId];
    if (budget.categoryId != null && cat == null) continue;
    final spent = budget.categoryId == null
        ? s.expense
        : s.expenseByCategory[budget.categoryId] ?? 0;
    out.add(BudgetStatus(budget: budget, category: cat, spent: spent, period: p));
  }
  out.sort((a, c) {
    if (a.isOverall != c.isOverall) return a.isOverall ? -1 : 1;
    return c.fraction.compareTo(a.fraction);
  });
  return AsyncData(out);
});

/// Upcoming bills: active rules due within [days] (overdue ones included).
class UpcomingBill {
  const UpcomingBill(this.rule, this.due);

  final RecurringRule rule;
  final DateTime due;
}

final upcomingBillsProvider = Provider.family<List<UpcomingBill>, int>((ref, days) {
  final today = ref.watch(todayProvider);
  final horizon = DateTime(today.year, today.month, today.day + days);
  final rules = ref.watch(recurringProvider).value ?? const <RecurringRule>[];
  return [
    for (final r in rules)
      if (r.active && r.kind != TxnKind.income && r.nextDue.isBefore(horizon))
        UpcomingBill(r, r.nextDue),
  ]..sort((a, b) => a.due.compareTo(b.due));
});
