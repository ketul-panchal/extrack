import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:spent/app/router.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/services/notifications.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/lock/lock_controller.dart';
import 'package:spent/features/lock/lock_screen.dart';

class SpentApp extends ConsumerStatefulWidget {
  const SpentApp({super.key});

  @override
  ConsumerState<SpentApp> createState() => _SpentAppState();
}

class _SpentAppState extends ConsumerState<SpentApp> with WidgetsBindingObserver {
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_catchUp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncDebounce?.cancel();
    super.dispose();
  }

  /// Posts recurring transactions that came due while the app was closed.
  Future<void> _catchUp() async {
    if (!ref.read(settingsProvider).onboarded) return;
    try {
      await ref.read(recurringRepositoryProvider).processDue(DateTime.now());
    } on Object catch (e, s) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s, library: 'recurring'));
    }
  }

  void _scheduleNotificationSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 800), () async {
      final settings = ref.read(settingsProvider);
      if (!settings.onboarded) return;
      try {
        await ref
            .read(notificationServiceProvider)
            .sync(
              settings: settings,
              rules: ref.read(recurringProvider).value ?? const <RecurringRule>[],
              categories: ref.read(categoryMapProvider),
              money: ref.read(moneyFormatProvider),
            );
      } on Object catch (e, s) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: s, library: 'notifications'),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockProvider.notifier);
    final obscure = ref.read(obscureProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        obscure.set(false);
        lock.onForeground();
        ref.read(todayProvider.notifier).refresh();
        unawaited(_catchUp());
      case AppLifecycleState.inactive:
        obscure.set(true);
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        obscure.set(true);
        lock.onBackground();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    Haptics.enabled = ref.watch(settingsProvider.select((s) => s.haptics));
    final router = ref.watch(routerProvider);

    // Keep scheduled reminders in step with settings and bills.
    ref.listen(recurringProvider, (_, _) => _scheduleNotificationSync());
    ref.listen(
      settingsProvider.select(
        (s) => (
          s.dailyReminder,
          s.reminderMinutes,
          s.billReminders,
          s.currencyCode,
          s.hideAmounts,
          s.onboarded,
        ),
      ),
      (_, _) => _scheduleNotificationSync(),
    );
    // Turning the lock off elsewhere should never leave the gate up.
    ref.listen(settingsProvider.select((s) => s.lockEnabled), (_, enabled) {
      if (!enabled) ref.read(lockProvider.notifier).unlock();
    });

    return PostHogWidget(
      child: MaterialApp.router(
        title: 'Spent',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(accent),
        darkTheme: AppTheme.dark(accent),
        themeMode: themeMode,
        themeAnimationDuration: const Duration(milliseconds: 350),
        themeAnimationCurve: Curves.easeInOutCubic,
        routerConfig: router,
        builder: (context, child) {
          final palette = Theme.of(context).extension<AppPalette>()!;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.overlayStyle(palette),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.35,
              child: LockGate(child: child ?? const SizedBox.shrink()),
            ),
          );
        },
      ),
    );
  }
}
