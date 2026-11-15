import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local-only reminders (nothing leaves the device): a daily nudge to log
/// spending and a heads-up on the day a bill is due.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _dailyId = 1;
  static const _billBase = 1000;

  static const _daily = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reminder',
      'Daily reminder',
      channelDescription: 'A gentle nudge to log the day\'s spending',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _bills = NotificationDetails(
    android: AndroidNotificationDetails(
      'bill_reminders',
      'Bill reminders',
      channelDescription: 'Recurring payments due today',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } on Object {
      // Keep UTC if the zone can't be resolved; reminders may shift.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_spent'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks the OS for permission. Returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    }
    return false;
  }

  /// Rebuilds every scheduled reminder from current settings and rules.
  Future<void> sync({
    required AppSettings settings,
    required List<RecurringRule> rules,
    required Map<int, Category> categories,
    required MoneyFormat money,
  }) async {
    await init();
    await _plugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);

    if (settings.dailyReminder) {
      final h = settings.reminderMinutes ~/ 60;
      final m = settings.reminderMinutes % 60;
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: _dailyId,
        title: 'Anything to log today?',
        body: 'Ten seconds now keeps your budget honest.',
        scheduledDate: at,
        notificationDetails: _daily,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    if (settings.billReminders) {
      final horizon = now.add(const Duration(days: 45));
      final due =
          rules
              .where((r) => r.active && r.kind == TxnKind.expense && r.nextDue.isBefore(horizon))
              .toList()
            ..sort((a, b) => a.nextDue.compareTo(b.nextDue));
      for (final r in due.take(40)) {
        final at = tz.TZDateTime(tz.local, r.nextDue.year, r.nextDue.month, r.nextDue.day, 9);
        if (!at.isAfter(now)) continue;
        final name = r.note.isNotEmpty ? r.note : (categories[r.categoryId]?.name ?? 'A bill');
        await _plugin.zonedSchedule(
          id: _billBase + r.id,
          title: '$name is due today',
          body:
              '${settings.hideAmounts ? 'A payment' : money.format(r.amount)} · '
              '${r.autoPost ? 'It will be recorded automatically.' : 'Open Spent to mark it paid.'}',
          scheduledDate: at,
          notificationDetails: _bills,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }
}

/// Overridden with a no-op in tests.
final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());
