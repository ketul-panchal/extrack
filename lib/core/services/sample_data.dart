import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/core/time/recurrence.dart';
import 'package:spent/data/category_repository.dart';

/// Builds a believable few months of history so every screen has something
/// to show. Deterministic (seeded) so it looks the same every time.
class SampleData {
  SampleData(this._db, this.currency);

  final AppDatabase _db;
  final Currency currency;
  final _r = math.Random(42);

  /// Rough purchasing-power scale from "base" amounts to this currency, so
  /// a coffee costs ~₹180 or ~$3.6, not ₹3.6.
  double get _scale => switch (currency.code) {
    'INR' || 'NPR' || 'BDT' => 50,
    'PKR' || 'LKR' => 150,
    'JPY' => 130,
    'KRW' => 1200,
    'IDR' => 14000,
    'VND' => 22000,
    'PHP' || 'RUB' || 'THB' => 45,
    'TRY' || 'UAH' => 30,
    'MXN' || 'ZAR' || 'EGP' => 18,
    'BRL' || 'MYR' || 'CNY' || 'HKD' || 'SEK' || 'NOK' || 'DKK' => 7,
    'NGN' => 1200,
    'KES' => 130,
    'AED' || 'SAR' || 'QAR' || 'ILS' || 'PLN' => 3.7,
    'KWD' => 0.3,
    'GBP' || 'EUR' || 'CHF' => 0.9,
    'AUD' || 'CAD' || 'NZD' || 'SGD' => 1.4,
    _ => 1,
  };

  int get _unit => math.pow(10, currency.decimals).toInt();

  /// Converts a base amount into friendly minor units (rounded to a natural step).
  int amt(double base, {double jitter = 0}) {
    var v = base * _scale;
    if (jitter > 0) v *= 1 + (_r.nextDouble() * 2 - 1) * jitter;
    final step = v >= 1000 ? 10 : (v >= 100 ? 5 : (v >= 10 ? 1 : 0.25));
    final rounded = math.max(step.toDouble(), (v / step).round() * step.toDouble());
    return (rounded * _unit).round();
  }

  T _pick<T>(List<T> list) => list[_r.nextInt(list.length)];

  Future<void> load() async {
    await CategoryRepository(_db).seedDefaults();
    final now = clock.now();
    final today = dateOnly(now);
    final cats = {for (final c in await _db.select(_db.categories).get()) c.name: c.id};

    Future<int> account(String name, AccountType type, int opening, {String? icon, int? color}) =>
        _db
            .into(_db.accounts)
            .insert(
              AccountsCompanion.insert(
                name: name,
                type: type,
                icon: icon ?? type.defaultIcon,
                color: color ?? defaultAccountColor(type),
                openingBalance: Value(opening),
                createdAt: now,
                sortOrder: Value(type.index),
              ),
            );

    final existing = await _db.select(_db.accounts).get();
    final bank =
        existing.where((a) => a.type == AccountType.bank).firstOrNull?.id ??
        await account('Bank account', AccountType.bank, amt(1800));
    final cash =
        existing.where((a) => a.type == AccountType.cash).firstOrNull?.id ??
        await account('Cash', AccountType.cash, amt(60));
    final card = await account('Credit card', AccountType.card, -amt(120));
    final wallet = await account(
      'Wallet',
      AccountType.wallet,
      amt(40),
      color: EntityColors.orange.light.toARGB32(),
    );

    final txns = <TxnsCompanion>[];
    void add(
      TxnKind kind,
      int amount,
      DateTime date, {
      String? category,
      int? account,
      int? to,
      String note = '',
      int? rule,
    }) {
      if (dateOnly(date).isAfter(today)) return;
      txns.add(
        TxnsCompanion.insert(
          kind: kind,
          amount: amount,
          accountId: account ?? bank,
          toAccountId: Value(to),
          categoryId: Value(category == null ? null : cats[category]),
          date: date,
          note: Value(note),
          recurringId: Value(rule),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    DateTime at(DateTime day, int hour, [int minute = 0]) =>
        DateTime(day.year, day.month, day.day, hour, minute + _r.nextInt(50));

    // Recurring rules (with their past occurrences recorded).
    Future<int> rule(
      String note,
      TxnKind kind,
      double base,
      String? category,
      int account,
      DateTime anchor, {
      Frequency f = Frequency.monthly,
      bool auto = true,
      DateTime? end,
    }) async {
      final rec = Recurrence(frequency: f, every: 1, anchor: anchor);
      // Auto rules have recorded today's occurrence already; manual ones
      // leave it waiting to be marked paid.
      var next = anchor;
      while (auto ? !next.isAfter(today) : next.isBefore(today)) {
        next = rec.after(next);
      }
      return _db
          .into(_db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              kind: kind,
              amount: amt(base),
              accountId: account,
              categoryId: Value(category == null ? null : cats[category]),
              note: Value(note),
              frequency: f,
              startDate: anchor,
              nextDue: next,
              endDate: Value(end),
              autoPost: Value(auto),
              createdAt: now,
            ),
          );
    }

    final start = DateTime(today.year - 1, today.month, 1);
    final emiStart = DateTime(today.year, today.month - 3, 10);
    final salaryRule = await rule(
      'Salary',
      TxnKind.income,
      2400,
      'Salary',
      bank,
      DateTime(start.year, start.month, 1),
    );
    final rentRule = await rule(
      'Rent',
      TxnKind.expense,
      600,
      'Housing',
      bank,
      DateTime(start.year, start.month, 3),
    );
    final netflixRule = await rule(
      'Netflix',
      TxnKind.expense,
      13,
      'Subscriptions',
      card,
      DateTime(start.year, start.month, 12),
    );
    final musicRule = await rule(
      'Spotify',
      TxnKind.expense,
      2.4,
      'Subscriptions',
      card,
      DateTime(start.year, start.month, 18),
    );
    final internetRule = await rule(
      'Internet',
      TxnKind.expense,
      20,
      'Bills & Utilities',
      bank,
      DateTime(start.year, start.month, 7),
      auto: false,
    );
    final gymRule = await rule(
      'Gym membership',
      TxnKind.expense,
      28,
      'Health',
      card,
      DateTime(start.year, start.month, 5),
    );
    final phoneEmiRule = await rule(
      'Phone EMI',
      TxnKind.expense,
      85,
      'Shopping',
      card,
      emiStart,
      end: DateTime(emiStart.year, emiStart.month + 11, 10),
    );

    // Month-by-month history.
    for (var day = start; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1)) {
      final weekend = day.weekday >= DateTime.saturday;
      if (day.day == 1) {
        add(
          TxnKind.income,
          amt(2400),
          at(day, 9),
          category: 'Salary',
          note: 'Salary',
          rule: salaryRule,
        );
      }
      if (day.day == 3) {
        add(
          TxnKind.expense,
          amt(600),
          at(day, 10),
          category: 'Housing',
          note: 'Rent',
          rule: rentRule,
        );
      }
      if (day.day == 12) {
        add(
          TxnKind.expense,
          amt(13),
          at(day, 8),
          category: 'Subscriptions',
          account: card,
          note: 'Netflix',
          rule: netflixRule,
        );
      }
      if (day.day == 18) {
        add(
          TxnKind.expense,
          amt(2.4),
          at(day, 8),
          category: 'Subscriptions',
          account: card,
          note: 'Spotify',
          rule: musicRule,
        );
      }
      if (day.day == 7 && day.isBefore(today)) {
        add(
          TxnKind.expense,
          amt(20),
          at(day, 19),
          category: 'Bills & Utilities',
          note: 'Internet',
          rule: internetRule,
        );
      }
      if (day.day == 5) {
        add(
          TxnKind.expense,
          amt(28),
          at(day, 7),
          category: 'Health',
          account: card,
          note: 'Gym membership',
          rule: gymRule,
        );
      }
      if (day.day == 10 && !day.isBefore(emiStart)) {
        add(
          TxnKind.expense,
          amt(85),
          at(day, 9),
          category: 'Shopping',
          account: card,
          note: 'Phone EMI',
          rule: phoneEmiRule,
        );
      }
      if (day.day == 9) {
        add(
          TxnKind.expense,
          amt(44, jitter: 0.25),
          at(day, 18),
          category: 'Bills & Utilities',
          note: 'Electricity bill',
        );
      }
      if (day.day == 15) {
        add(
          TxnKind.expense,
          amt(8),
          at(day, 12),
          category: 'Bills & Utilities',
          account: wallet,
          note: 'Mobile recharge',
        );
      }
      if (day.day == 2) {
        add(
          TxnKind.transfer,
          amt(100),
          at(day, 13),
          account: bank,
          to: cash,
          note: 'ATM withdrawal',
        );
      }
      if (day.day == 20) {
        add(TxnKind.transfer, amt(220), at(day, 11), account: bank, to: card, note: 'Card payment');
      }
      if (day.day == 10) {
        add(
          TxnKind.transfer,
          amt(40),
          at(day, 11),
          account: bank,
          to: wallet,
          note: 'Wallet top-up',
        );
      }
      if (day.day == 24 && _r.nextBool()) {
        add(
          TxnKind.income,
          amt(300, jitter: 0.3),
          at(day, 16),
          category: 'Freelance',
          note: 'Design project',
        );
      }

      // Everyday spending.
      if (_r.nextDouble() < (weekend ? 0.7 : 0.45)) {
        add(
          TxnKind.expense,
          amt(weekend ? 16 : 7, jitter: 0.5),
          at(day, weekend ? 20 : 13),
          category: 'Food & Dining',
          account: _pick([card, wallet, cash]),
          note: _pick(
            weekend
                ? ['Dinner out', 'Brunch', 'Pizza night', 'Sushi']
                : ['Lunch', 'Takeaway', 'Street food'],
          ),
        );
      }
      if (!weekend && _r.nextDouble() < 0.45) {
        add(
          TxnKind.expense,
          amt(3.2, jitter: 0.3),
          at(day, 9),
          category: 'Food & Dining',
          account: _pick([wallet, cash]),
          note: _pick(['Coffee', 'Cappuccino', 'Tea & snacks']),
        );
      }
      if (day.weekday == DateTime.sunday || (day.weekday == DateTime.wednesday && _r.nextBool())) {
        add(
          TxnKind.expense,
          amt(day.weekday == DateTime.sunday ? 48 : 18, jitter: 0.35),
          at(day, 11),
          category: 'Groceries',
          account: _pick([card, bank]),
          note: _pick(['Weekly groceries', 'Supermarket', 'Fruits & veggies']),
        );
      }
      if (!weekend && _r.nextDouble() < 0.35) {
        add(
          TxnKind.expense,
          amt(5, jitter: 0.5),
          at(day, 8),
          category: 'Transport',
          account: _pick([wallet, cash]),
          note: _pick(['Cab ride', 'Metro', 'Bus pass top-up']),
        );
      }
      if (day.day % 11 == 4) {
        add(
          TxnKind.expense,
          amt(40, jitter: 0.2),
          at(day, 18),
          category: 'Transport',
          account: card,
          note: 'Fuel',
        );
      }
      if (_r.nextDouble() < 0.09) {
        add(
          TxnKind.expense,
          amt(45, jitter: 0.6),
          at(day, 17),
          category: 'Shopping',
          account: card,
          note: _pick(['Clothes', 'Shoes', 'Headphones', 'Home decor', 'Books']),
        );
      }
      if (weekend && _r.nextDouble() < 0.3) {
        add(
          TxnKind.expense,
          amt(14, jitter: 0.5),
          at(day, 19),
          category: 'Entertainment',
          account: card,
          note: _pick(['Movie tickets', 'Concert', 'Bowling', 'Game']),
        );
      }
      if (_r.nextDouble() < 0.04) {
        add(
          TxnKind.expense,
          amt(18, jitter: 0.6),
          at(day, 15),
          category: 'Health',
          account: cash,
          note: _pick(['Pharmacy', 'Doctor visit', 'Vitamins']),
        );
      }
      if (_r.nextDouble() < 0.035) {
        add(
          TxnKind.expense,
          amt(12, jitter: 0.4),
          at(day, 12),
          category: 'Personal Care',
          account: wallet,
          note: _pick(['Haircut', 'Skincare']),
        );
      }
      if (_r.nextDouble() < 0.02) {
        add(
          TxnKind.expense,
          amt(25, jitter: 0.5),
          at(day, 14),
          category: 'Gifts & Donations',
          account: card,
          note: _pick(['Birthday gift', 'Charity']),
        );
      }
    }
    await _db.batch((b) => b.insertAll(_db.txns, txns));

    // Budgets: overall plus a few categories.
    Future<void> budget(String? category, double base) => _db
        .into(_db.budgets)
        .insert(
          BudgetsCompanion.insert(
            categoryId: Value(category == null ? null : cats[category]),
            amount: amt(base),
            createdAt: now,
          ),
        );
    await budget(null, 1500);
    await budget('Food & Dining', 230);
    await budget('Groceries', 200);
    await budget('Shopping', 110);
    await budget('Transport', 120);
    await budget('Entertainment', 50);

    // Goals with a little history.
    Future<void> goal(
      String name,
      String icon,
      EntityColor color,
      double target,
      List<double> deposits, {
      DateTime? deadline,
    }) async {
      final id = await _db
          .into(_db.goals)
          .insert(
            GoalsCompanion.insert(
              name: name,
              target: amt(target),
              icon: icon,
              color: color.light.toARGB32(),
              deadline: Value(deadline),
              createdAt: start,
            ),
          );
      for (var i = 0; i < deposits.length; i++) {
        await _db
            .into(_db.goalEntries)
            .insert(
              GoalEntriesCompanion.insert(
                goalId: id,
                amount: amt(deposits[i]),
                date: DateTime(start.year, start.month + i, 4, 10),
              ),
            );
      }
    }

    await goal('Emergency fund', 'piggy', EntityColors.aqua, 4500, [900, 700, 600, 300]);
    await goal('Trip to Japan', 'flight', EntityColors.rose, 3000, [
      400,
      250,
      300,
    ], deadline: DateTime(today.year, today.month + 8, 1));
    await goal('New laptop', 'laptop', EntityColors.indigo, 1800, [800, 500, 360]);
  }
}
