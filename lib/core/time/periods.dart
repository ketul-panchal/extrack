import 'package:intl/intl.dart';

enum PeriodType {
  week('Week'),
  month('Month'),
  year('Year');

  const PeriodType(this.label);
  final String label;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Whole calendar days from [a] to [b] (dates only, DST-safe).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// A half-open range of whole days: [start, end).
class Period {
  const Period(this.type, this.start, this.end);

  final PeriodType type;
  final DateTime start;
  final DateTime end;

  int get days => daysBetween(start, end);

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// The last day inside the period.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  /// Days elapsed including today, clamped to the period.
  int elapsedDays(DateTime now) {
    if (now.isBefore(start)) return 0;
    if (!now.isBefore(end)) return days;
    return daysBetween(start, now) + 1;
  }

  /// Days remaining including today.
  int remainingDays(DateTime now) {
    if (!now.isBefore(end)) return 0;
    if (now.isBefore(start)) return days;
    return daysBetween(now, end);
  }

  bool isCurrent(DateTime now) => contains(now);

  @override
  bool operator ==(Object other) =>
      other is Period && other.type == type && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(type, start, end);

  @override
  String toString() => 'Period(${type.name}, $start → $end)';
}

/// Builds periods from the user's preferences: the day budgets reset each
/// month (salary cycles) and the first day of the week.
class PeriodCalculator {
  const PeriodCalculator({this.monthStartDay = 1, this.weekStartDay = DateTime.monday});

  /// 1–28. With 25, "October" runs 25 Sep → 24 Oct.
  final int monthStartDay;

  /// [DateTime.monday] … [DateTime.sunday].
  final int weekStartDay;

  Period of(PeriodType type, DateTime d) => switch (type) {
    PeriodType.week => week(d),
    PeriodType.month => month(d),
    PeriodType.year => year(d),
  };

  Period month(DateTime d) {
    final startDay = monthStartDay.clamp(1, 28);
    final start = d.day >= startDay
        ? DateTime(d.year, d.month, startDay)
        : DateTime(d.year, d.month - 1, startDay);
    return Period(PeriodType.month, start, DateTime(start.year, start.month + 1, startDay));
  }

  Period week(DateTime d) {
    final offset = (d.weekday - weekStartDay + 7) % 7;
    final start = DateTime(d.year, d.month, d.day - offset);
    return Period(PeriodType.week, start, DateTime(start.year, start.month, start.day + 7));
  }

  Period year(DateTime d) => Period(PeriodType.year, DateTime(d.year), DateTime(d.year + 1));

  Period shift(Period p, int by) {
    if (by == 0) return p;
    return switch (p.type) {
      PeriodType.week => week(DateTime(p.start.year, p.start.month, p.start.day + 7 * by)),
      PeriodType.month => month(DateTime(p.start.year, p.start.month + by, p.start.day)),
      PeriodType.year => year(DateTime(p.start.year + by)),
    };
  }

  Period previous(Period p) => shift(p, -1);
  Period next(Period p) => shift(p, 1);

  /// "October 2026", "25 Sep – 24 Oct", "6 – 12 Oct", "2026".
  String label(Period p, {DateTime? now}) {
    final today = now ?? DateTime.now();
    switch (p.type) {
      case PeriodType.year:
        return '${p.start.year}';
      case PeriodType.week:
        return rangeLabel(p.start, p.lastDay, now: today);
      case PeriodType.month:
        if (monthStartDay == 1) {
          return p.start.year == today.year
              ? DateFormat('MMMM').format(p.start)
              : DateFormat('MMMM yyyy').format(p.start);
        }
        return rangeLabel(p.start, p.lastDay, now: today);
    }
  }

  /// Short name used in comparisons: "last month", "last week", "last year".
  static String previousName(PeriodType type) => switch (type) {
    PeriodType.week => 'last week',
    PeriodType.month => 'last month',
    PeriodType.year => 'last year',
  };
}

/// "6 – 12 Oct", "29 Sep – 5 Oct", "28 Dec 2025 – 3 Jan 2026".
String rangeLabel(DateTime a, DateTime b, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (a.year != b.year || a.year != today.year) {
    return '${DateFormat('d MMM yyyy').format(a)} – ${DateFormat('d MMM yyyy').format(b)}';
  }
  if (a.month == b.month) return '${a.day} – ${DateFormat('d MMM').format(b)}';
  return '${DateFormat('d MMM').format(a)} – ${DateFormat('d MMM').format(b)}';
}
