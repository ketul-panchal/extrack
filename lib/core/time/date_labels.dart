import 'package:intl/intl.dart';
import 'package:spent/core/time/periods.dart';

/// Human labels for days relative to [now].
abstract final class DateLabels {
  /// "Today", "Yesterday", "Tomorrow", "Monday" (this week), "6 Oct", "6 Oct 2025".
  static String day(DateTime d, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final diff = daysBetween(today, d);
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    if (diff < 0 && diff > -7) return DateFormat('EEEE').format(d);
    if (d.year == today.year) return DateFormat('EEE, d MMM').format(d);
    return DateFormat('d MMM yyyy').format(d);
  }

  /// Short chip label: "Today", "Yesterday", "Mon, 6 Oct".
  static String chip(DateTime d, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final diff = daysBetween(today, d);
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    if (d.year == today.year) return DateFormat('EEE, d MMM').format(d);
    return DateFormat('d MMM yyyy').format(d);
  }

  /// "in 3 days", "tomorrow", "today", "2 days ago".
  static String due(DateTime d, {DateTime? now}) {
    final diff = daysBetween(dateOnly(now ?? DateTime.now()), d);
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    if (diff == -1) return 'yesterday';
    if (diff > 1) return diff < 60 ? 'in $diff days' : 'on ${DateFormat('d MMM').format(d)}';
    return '${-diff} days ago';
  }

  static String full(DateTime d) => DateFormat('EEEE, d MMMM yyyy').format(d);
  static String short(DateTime d) => DateFormat('d MMM yyyy').format(d);
  static String time(DateTime d) => DateFormat('h:mm a').format(d);
  static String monthYear(DateTime d) => DateFormat('MMMM yyyy').format(d);

  /// "Good morning" style greeting.
  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Good night';
  }
}
