import 'package:flutter_test/flutter_test.dart';
import 'package:spent/core/database/enums.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/core/time/recurrence.dart';

void main() {
  group('PeriodCalculator', () {
    test('calendar month', () {
      const calc = PeriodCalculator();
      final p = calc.month(DateTime(2026, 10, 8, 15));
      expect(p.start, DateTime(2026, 10));
      expect(p.end, DateTime(2026, 11));
      expect(p.days, 31);
      expect(p.contains(DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(p.contains(DateTime(2026, 11)), isFalse);
    });

    test('salary cycle starting on the 25th', () {
      const calc = PeriodCalculator(monthStartDay: 25);
      final before = calc.month(DateTime(2026, 10, 8));
      expect(before.start, DateTime(2026, 9, 25));
      expect(before.end, DateTime(2026, 10, 25));
      final after = calc.month(DateTime(2026, 10, 25));
      expect(after.start, DateTime(2026, 10, 25));
      // Crosses the year boundary.
      final jan = calc.month(DateTime(2027, 1, 3));
      expect(jan.start, DateTime(2026, 12, 25));
      expect(jan.end, DateTime(2027, 1, 25));
    });

    test('weeks honour the first weekday', () {
      const monday = PeriodCalculator();
      const sunday = PeriodCalculator(weekStartDay: DateTime.sunday);
      final thursday = DateTime(2026, 10, 8);
      expect(monday.week(thursday).start, DateTime(2026, 10, 5));
      expect(sunday.week(thursday).start, DateTime(2026, 10, 4));
      expect(monday.week(DateTime(2026, 10, 5)).start, DateTime(2026, 10, 5));
    });

    test('shift moves by whole periods', () {
      const calc = PeriodCalculator(monthStartDay: 25);
      final p = calc.month(DateTime(2026, 10, 8));
      expect(calc.previous(p).start, DateTime(2026, 8, 25));
      expect(calc.next(p).start, DateTime(2026, 10, 25));
      final y = calc.year(DateTime(2026, 3, 3));
      expect(calc.next(y).start, DateTime(2027));
    });

    test('elapsed and remaining days include today', () {
      const calc = PeriodCalculator();
      final p = calc.month(DateTime(2026, 10, 1));
      expect(p.elapsedDays(DateTime(2026, 10, 1, 9)), 1);
      expect(p.remainingDays(DateTime(2026, 10, 1, 9)), 31);
      expect(p.elapsedDays(DateTime(2026, 10, 31, 9)), 31);
      expect(p.remainingDays(DateTime(2026, 10, 31, 9)), 1);
      expect(p.remainingDays(DateTime(2026, 11, 2)), 0);
    });

    test('labels', () {
      const calc = PeriodCalculator();
      final now = DateTime(2026, 10, 8);
      expect(calc.label(calc.month(now), now: now), 'October');
      expect(calc.label(calc.month(DateTime(2025, 10, 8)), now: now), 'October 2025');
      expect(calc.label(calc.week(now), now: now), '5 – 11 Oct');
      const cycle = PeriodCalculator(monthStartDay: 25);
      expect(cycle.label(cycle.month(now), now: now), '25 Sep – 24 Oct');
    });
  });

  group('Recurrence', () {
    test('monthly on the 31st clamps to short months and recovers', () {
      final r = Recurrence(frequency: Frequency.monthly, every: 1, anchor: DateTime(2026, 1, 31));
      expect(r.after(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      expect(r.after(DateTime(2026, 2, 28)), DateTime(2026, 3, 31));
      expect(r.after(DateTime(2026, 3, 31)), DateTime(2026, 4, 30));
    });

    test('leap years', () {
      final monthly = Recurrence(
        frequency: Frequency.monthly,
        every: 1,
        anchor: DateTime(2028, 1, 30),
      );
      expect(monthly.after(DateTime(2028, 1, 30)), DateTime(2028, 2, 29));
      final yearly = Recurrence(
        frequency: Frequency.yearly,
        every: 1,
        anchor: DateTime(2028, 2, 29),
      );
      expect(yearly.after(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
      expect(yearly.after(DateTime(2031, 2, 28)), DateTime(2032, 2, 29));
    });

    test('every N units and across year ends', () {
      final twoMonths = Recurrence(
        frequency: Frequency.monthly,
        every: 2,
        anchor: DateTime(2026, 11, 15),
      );
      expect(twoMonths.after(DateTime(2026, 11, 15)), DateTime(2027, 1, 15));
      final biweekly = Recurrence(
        frequency: Frequency.weekly,
        every: 2,
        anchor: DateTime(2026, 12, 25),
      );
      expect(biweekly.after(DateTime(2026, 12, 25)), DateTime(2027, 1, 8));
      final daily = Recurrence(
        frequency: Frequency.daily,
        every: 1,
        anchor: DateTime(2026, 12, 31),
      );
      expect(daily.after(DateTime(2026, 12, 31)), DateTime(2027));
    });

    test('occurrences between dates', () {
      final r = Recurrence(frequency: Frequency.monthly, every: 1, anchor: DateTime(2026, 1, 1));
      final list = r.occurrences(DateTime(2026, 1, 1), DateTime(2026, 4, 1));
      expect(list, [DateTime(2026, 1), DateTime(2026, 2), DateTime(2026, 3), DateTime(2026, 4)]);
    });
  });
}
