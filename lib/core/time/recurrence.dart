import 'dart:math' as math;

import 'package:spent/core/database/enums.dart';
import 'package:spent/core/time/periods.dart';

/// Date math for repeating transactions. All dates are local, date-only.
class Recurrence {
  const Recurrence({required this.frequency, required this.every, required this.anchor});

  final Frequency frequency;

  /// Repeat every N units (≥ 1).
  final int every;

  /// The first occurrence; its day (and month, for yearly) is kept even when a
  /// shorter month forces an earlier day. A rule on the 31st posts on Feb 28
  /// and then on Mar 31 again.
  final DateTime anchor;

  DateTime after(DateTime current) {
    final n = math.max(1, every);
    final c = dateOnly(current);
    switch (frequency) {
      case Frequency.daily:
        return DateTime(c.year, c.month, c.day + n);
      case Frequency.weekly:
        return DateTime(c.year, c.month, c.day + 7 * n);
      case Frequency.monthly:
        final total = c.year * 12 + (c.month - 1) + n;
        final y = total ~/ 12;
        final m = total % 12 + 1;
        return DateTime(y, m, math.min(anchor.day, daysInMonth(y, m)));
      case Frequency.yearly:
        final y = c.year + n;
        return DateTime(y, anchor.month, math.min(anchor.day, daysInMonth(y, anchor.month)));
    }
  }

  /// Occurrences from [from] (inclusive, must be an occurrence) up to and
  /// including [until], capped at [limit] to stay safe on bad data.
  List<DateTime> occurrences(DateTime from, DateTime until, {int limit = 500}) {
    final out = <DateTime>[];
    var d = dateOnly(from);
    final end = dateOnly(until);
    while (!d.isAfter(end) && out.length < limit) {
      out.add(d);
      d = after(d);
    }
    return out;
  }
}
