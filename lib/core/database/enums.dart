/// Stored by name (`textEnum`), so reordering these never corrupts data.
/// Only add new values; renaming one needs a migration.
library;

enum TxnKind {
  expense,
  income,
  transfer;

  String get label => switch (this) {
    TxnKind.expense => 'Expense',
    TxnKind.income => 'Income',
    TxnKind.transfer => 'Transfer',
  };
}

enum CategoryKind {
  expense,
  income;

  String get label => switch (this) {
    CategoryKind.expense => 'Expense',
    CategoryKind.income => 'Income',
  };

  TxnKind get txnKind => switch (this) {
    CategoryKind.expense => TxnKind.expense,
    CategoryKind.income => TxnKind.income,
  };
}

enum AccountType {
  cash,
  bank,
  card,
  wallet,
  savings,
  investment,
  other;

  String get label => switch (this) {
    AccountType.cash => 'Cash',
    AccountType.bank => 'Bank account',
    AccountType.card => 'Credit card',
    AccountType.wallet => 'Digital wallet',
    AccountType.savings => 'Savings',
    AccountType.investment => 'Investment',
    AccountType.other => 'Other',
  };

  /// Icon key from `AppIcons` used when an account of this type is created.
  String get defaultIcon => switch (this) {
    AccountType.cash => 'cash',
    AccountType.bank => 'bank',
    AccountType.card => 'card',
    AccountType.wallet => 'wallet',
    AccountType.savings => 'piggy',
    AccountType.investment => 'chart',
    AccountType.other => 'account',
  };

  /// Credit cards normally carry a balance below zero (money owed).
  bool get isLiability => this == AccountType.card;
}

enum Frequency {
  daily,
  weekly,
  monthly,
  yearly;

  String label(int every) => switch (this) {
    Frequency.daily => every == 1 ? 'Daily' : 'Every $every days',
    Frequency.weekly => every == 1 ? 'Weekly' : 'Every $every weeks',
    Frequency.monthly => every == 1 ? 'Monthly' : 'Every $every months',
    Frequency.yearly => every == 1 ? 'Yearly' : 'Every $every years',
  };

  String get unit => switch (this) {
    Frequency.daily => 'day',
    Frequency.weekly => 'week',
    Frequency.monthly => 'month',
    Frequency.yearly => 'year',
  };

  /// Approximate occurrences per month, for "monthly cost" summaries.
  double perMonth(int every) => switch (this) {
    Frequency.daily => 30.4375 / every,
    Frequency.weekly => 4.348125 / every,
    Frequency.monthly => 1 / every,
    Frequency.yearly => 1 / (12 * every),
  };
}
