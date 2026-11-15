import 'package:material_ui/material_ui.dart' show immutable;
import 'package:spent/core/database/database.dart';

/// A transaction with the rows it points at, ready to display.
class TxnView {
  const TxnView(this.txn, {this.category, this.account, this.toAccount});

  final Txn txn;
  final Category? category;
  final Account? account;
  final Account? toAccount;

  bool get isTransfer => txn.kind == TxnKind.transfer;
  bool get isIncome => txn.kind == TxnKind.income;
  bool get isExpense => txn.kind == TxnKind.expense;

  /// The note when there is one, otherwise what it was.
  String get title {
    if (txn.note.trim().isNotEmpty) return txn.note.trim();
    if (isTransfer) return 'Transfer';
    return category?.name ?? 'Uncategorized';
  }

  /// Where the money moved: "Food & Dining · Cash", "Bank → Cash".
  String get subtitle {
    if (isTransfer) return '${account?.name ?? '—'} → ${toAccount?.name ?? '—'}';
    final parts = <String>[
      if (txn.note.trim().isNotEmpty) category?.name ?? 'Uncategorized',
      ?account?.name,
    ];
    return parts.join(' · ');
  }

  /// Signed effect on total spending: expenses negative, income positive.
  int get signedAmount => switch (txn.kind) {
    TxnKind.expense => -txn.amount,
    TxnKind.income => txn.amount,
    TxnKind.transfer => 0,
  };

  String get iconKey {
    if (isTransfer) return 'repeat';
    return category?.icon ?? 'other';
  }

  static List<TxnView> build(
    Iterable<Txn> txns,
    Map<int, Category> categories,
    Map<int, Account> accounts,
  ) => [
    for (final t in txns)
      TxnView(
        t,
        category: t.categoryId == null ? null : categories[t.categoryId],
        account: accounts[t.accountId],
        toAccount: t.toAccountId == null ? null : accounts[t.toAccountId],
      ),
  ];
}

/// A goal with the money saved toward it so far.
class GoalProgress {
  const GoalProgress(this.goal, this.saved, this.entries);

  final Goal goal;
  final int saved;
  final int entries;

  double get fraction => goal.target <= 0 ? 0 : (saved / goal.target).clamp(0.0, 1.0);
  int get remaining => (goal.target - saved).clamp(0, goal.target);
  bool get reached => saved >= goal.target;
}

/// A past note to offer while typing, with the category it usually gets.
class NoteSuggestion {
  const NoteSuggestion({
    required this.note,
    required this.categoryId,
    required this.lastAmount,
    required this.uses,
  });

  final String note;
  final int? categoryId;
  final int lastAmount;
  final int uses;
}

enum TxnSort {
  newest('Newest first'),
  oldest('Oldest first'),
  largest('Largest first'),
  smallest('Smallest first');

  const TxnSort(this.label);
  final String label;
}

@immutable
class TxnFilter {
  const TxnFilter({
    this.query = '',
    this.kinds = const {},
    this.categoryIds = const {},
    this.accountIds = const {},
    this.from,
    this.to,
    this.minAmount,
    this.maxAmount,
    this.sort = TxnSort.newest,
  });

  final String query;
  final Set<TxnKind> kinds;
  final Set<int> categoryIds;
  final Set<int> accountIds;

  /// Inclusive start / exclusive end.
  final DateTime? from;
  final DateTime? to;
  final int? minAmount;
  final int? maxAmount;
  final TxnSort sort;

  bool get hasFilters =>
      kinds.isNotEmpty ||
      categoryIds.isNotEmpty ||
      accountIds.isNotEmpty ||
      from != null ||
      to != null ||
      minAmount != null ||
      maxAmount != null;

  int get filterCount =>
      (kinds.isNotEmpty ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (accountIds.isNotEmpty ? 1 : 0) +
      (from != null || to != null ? 1 : 0) +
      (minAmount != null || maxAmount != null ? 1 : 0);

  bool get isEmpty => query.trim().isEmpty && !hasFilters;

  TxnFilter copyWith({
    String? query,
    Set<TxnKind>? kinds,
    Set<int>? categoryIds,
    Set<int>? accountIds,
    DateTime? Function()? from,
    DateTime? Function()? to,
    int? Function()? minAmount,
    int? Function()? maxAmount,
    TxnSort? sort,
  }) => TxnFilter(
    query: query ?? this.query,
    kinds: kinds ?? this.kinds,
    categoryIds: categoryIds ?? this.categoryIds,
    accountIds: accountIds ?? this.accountIds,
    from: from != null ? from() : this.from,
    to: to != null ? to() : this.to,
    minAmount: minAmount != null ? minAmount() : this.minAmount,
    maxAmount: maxAmount != null ? maxAmount() : this.maxAmount,
    sort: sort ?? this.sort,
  );

  TxnFilter clearFilters() => TxnFilter(query: query, sort: sort);

  static bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

  @override
  bool operator ==(Object other) =>
      other is TxnFilter &&
      other.query == query &&
      _setEq(other.kinds, kinds) &&
      _setEq(other.categoryIds, categoryIds) &&
      _setEq(other.accountIds, accountIds) &&
      other.from == from &&
      other.to == to &&
      other.minAmount == minAmount &&
      other.maxAmount == maxAmount &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    query,
    Object.hashAllUnordered(kinds),
    Object.hashAllUnordered(categoryIds),
    Object.hashAllUnordered(accountIds),
    from,
    to,
    minAmount,
    maxAmount,
    sort,
  );
}
