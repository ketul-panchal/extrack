import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/services/backup_service.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/services/notifications.dart';
import 'package:spent/core/services/sample_data.dart';
import 'package:spent/core/services/security.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/lock/lock_controller.dart';
import 'package:spent/features/lock/lock_screen.dart';
import 'package:spent/features/lock/pin_widgets.dart';
import 'package:spent/features/pickers/picker_sheets.dart';
import 'package:spent/features/settings/currency_sheet.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/segmented.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';

const appVersion = '1.0.0';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _bioAvailable = false;
  String _bioLabel = 'Biometrics';
  bool _busy = false;

  SettingsController get _settings => ref.read(settingsProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(_checkBiometrics());
  }

  Future<void> _checkBiometrics() async {
    final bio = ref.read(biometricsProvider);
    final available = await bio.available();
    final label = await bio.label();
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioLabel = label;
      });
    }
  }

  void _toast(
    String message, {
    IconData icon = Icons.check_circle_rounded,
    ToastTone tone = ToastTone.success,
  }) {
    if (mounted) AppToast.show(context, message, icon: icon, tone: tone);
  }

  // ── General ──────────────────────────────────────────────────────────────

  Future<void> _editName() async {
    final controller = TextEditingController(text: ref.read(settingsProvider).name);
    final name = await showAppSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your name', style: ctx.text.headlineSmall),
            const Gap(4),
            Text('Used only for the greeting on Home.', style: ctx.text.bodySmall),
            const Gap(Insets.lg),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 24,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'First name', counterText: ''),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const Gap(Insets.lg),
            AppButton(label: 'Save', onPressed: () => Navigator.pop(ctx, controller.text)),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name != null) await _settings.update((s) => s.copyWith(name: name.trim()));
  }

  Future<void> _pickCurrency() async {
    final c = await showCurrencySheet(context, selected: ref.read(settingsProvider).currencyCode);
    if (c == null) return;
    await _settings.update((s) => s.copyWith(currencyCode: c.code, numberStyle: c.style));
  }

  Future<void> _pickNumberStyle() async {
    final current = ref.read(settingsProvider);
    final style = await showAppSheet<NumberStyle>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Number format'),
          for (final st in NumberStyle.values)
            OptionRow(
              title: MoneyFormat(current.currency, st).format(123456789),
              subtitle: switch (st) {
                NumberStyle.western => 'Thousands grouping',
                NumberStyle.indian => 'Lakh & crore grouping',
                NumberStyle.european => 'Dots for thousands, comma for decimals',
                NumberStyle.spaced => 'Spaces for thousands, comma for decimals',
              },
              selected: st == current.numberStyle,
              onTap: () => Navigator.pop(ctx, st),
            ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (style != null) await _settings.update((s) => s.copyWith(numberStyle: style));
  }

  Future<void> _pickMonthStart() async {
    final current = ref.read(settingsProvider).monthStartDay;
    final day = await showAppSheet<int>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(
            title: 'Month starts on',
            subtitle:
                'Budgets and monthly totals reset on this day. Pick your payday to budget salary to salary.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.xl),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= 28; d++)
                  Pressable(
                    onTap: () => Navigator.pop(ctx, d),
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: d == current ? ctx.palette.primary : ctx.palette.surface2,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$d',
                        style: ctx.text.titleSmall?.copyWith(
                          color: d == current ? ctx.palette.onPrimary : ctx.palette.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (day != null) await _settings.update((s) => s.copyWith(monthStartDay: day));
  }

  Future<void> _pickWeekStart() async {
    final current = ref.read(settingsProvider).weekStartDay;
    const days = {
      DateTime.monday: 'Monday',
      DateTime.saturday: 'Saturday',
      DateTime.sunday: 'Sunday',
    };
    final day = await showAppSheet<int>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Week starts on'),
          for (final e in days.entries)
            OptionRow(
              title: e.value,
              selected: e.key == current,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (day != null) await _settings.update((s) => s.copyWith(weekStartDay: day));
  }

  Future<void> _pickDefaultAccount() async {
    final id = await pickAccount(
      context,
      selected: ref.read(settingsProvider).defaultAccountId,
      title: 'Default account',
    );
    if (id != null) await _settings.update((s) => s.copyWith(defaultAccountId: () => id));
  }

  // ── Security ─────────────────────────────────────────────────────────────

  Future<bool?> _pinScreen(Widget screen) => Navigator.of(
    context,
    rootNavigator: true,
  ).push<bool>(MaterialPageRoute(builder: (_) => screen, fullscreenDialog: true));

  Future<void> _toggleLock(bool on) async {
    if (on) {
      final created = await _pinScreen(const PinScreen.create());
      if (created != true) return;
      await _settings.update(
        (s) => s.copyWith(lockEnabled: true, biometricsEnabled: _bioAvailable),
      );
      _toast(
        _bioAvailable ? 'App lock on · $_bioLabel enabled' : 'App lock on',
        icon: Icons.lock_rounded,
      );
    } else {
      final ok = await _pinScreen(const PinScreen.verify());
      if (ok != true) return;
      await ref.read(pinVaultProvider).clear();
      await _settings.update((s) => s.copyWith(lockEnabled: false, biometricsEnabled: false));
      ref.read(lockProvider.notifier).unlock();
      _toast('App lock off', icon: Icons.lock_open_rounded, tone: ToastTone.neutral);
    }
  }

  Future<void> _changePin() async {
    final ok = await _pinScreen(const PinScreen.verify());
    if (ok != true) return;
    final created = await _pinScreen(const PinScreen.create());
    if (created == true) _toast('PIN changed', icon: Icons.lock_rounded);
  }

  Future<void> _toggleBiometrics(bool on) async {
    if (on) {
      final ok = await ref
          .read(lockProvider.notifier)
          .withoutLock(
            () => ref.read(biometricsProvider).authenticate('Turn on $_bioLabel for Spent'),
          );
      if (!ok) return;
    }
    await _settings.update((s) => s.copyWith(biometricsEnabled: on));
  }

  Future<void> _pickLockAfter() async {
    final current = ref.read(settingsProvider).lockAfterSeconds;
    const options = {
      0: 'Immediately',
      30: 'After 30 seconds',
      60: 'After 1 minute',
      300: 'After 5 minutes',
      900: 'After 15 minutes',
    };
    final v = await showAppSheet<int>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(
            title: 'Lock when away',
            subtitle: 'How long Spent can be in the background before asking for the PIN.',
          ),
          for (final e in options.entries)
            OptionRow(
              title: e.value,
              selected: e.key == current,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (v != null) await _settings.update((s) => s.copyWith(lockAfterSeconds: v));
  }

  // ── Notifications ────────────────────────────────────────────────────────

  Future<bool> _ensurePermission() async {
    try {
      final ok = await ref.read(notificationServiceProvider).requestPermission();
      if (!ok) {
        _toast(
          'Notifications are off for Spent in system settings',
          icon: Icons.notifications_off_outlined,
          tone: ToastTone.warning,
        );
      }
      return ok;
    } on Object {
      return false;
    }
  }

  Future<void> _toggleReminder(bool on) async {
    if (on && !await _ensurePermission()) return;
    await _settings.update((s) => s.copyWith(dailyReminder: on));
  }

  Future<void> _pickReminderTime() async {
    final m = ref.read(settingsProvider).reminderMinutes;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t != null) {
      await _settings.update((s) => s.copyWith(reminderMinutes: t.hour * 60 + t.minute));
    }
  }

  Future<void> _toggleBills(bool on) async {
    if (on && !await _ensurePermission()) return;
    await _settings.update((s) => s.copyWith(billReminders: on));
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  BackupService get _backup => BackupService(ref.read(databaseProvider));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      _toast(e.message, icon: Icons.error_outline_rounded, tone: ToastTone.danger);
    } on Object catch (e) {
      _toast('Something went wrong: $e', icon: Icons.error_outline_rounded, tone: ToastTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() => _run(() async {
    final bytes = await _backup.csv(ref.read(moneyFormatProvider));
    final uri = await ref
        .read(lockProvider.notifier)
        .withoutLock(
          () => FilePicker.saveFile(
            fileName: 'spent-transactions-${BackupService.fileStamp(DateTime.now())}.csv',
            bytes: bytes,
            mimeType: 'text/csv',
            dialogTitle: 'Save transactions',
          ),
        );
    if (uri != null) _toast('Transactions exported', icon: Icons.table_view_rounded);
  });

  Future<void> _backupNow() => _run(() async {
    final bytes = await _backup.exportBytes(settings: ref.read(settingsProvider).toBackupJson());
    final uri = await ref
        .read(lockProvider.notifier)
        .withoutLock(
          () => FilePicker.saveFile(
            fileName: 'spent-backup-${BackupService.fileStamp(DateTime.now())}.json',
            bytes: bytes,
            mimeType: 'application/json',
            dialogTitle: 'Save backup',
          ),
        );
    if (uri != null) _toast('Backup saved', icon: Icons.cloud_done_outlined);
  });

  Future<void> _restore() => _run(() async {
    final file = await ref.read(lockProvider.notifier).withoutLock(FilePicker.pickFile);
    if (file == null) return;
    final service = _backup;
    final json = service.decode(await file.readAsBytes());
    final summary = service.summarize(json);
    if (!mounted) return;
    final when = summary.exportedAt == null
        ? ''
        : ' from ${MaterialLocalizations.of(context).formatMediumDate(summary.exportedAt!)}';
    final ok = await confirmSheet(
      context,
      title: 'Restore this backup?',
      message:
          'Backup$when with ${summary.transactions} transactions, ${summary.accounts} accounts and '
          '${summary.goals} goals. Everything currently in Spent will be replaced.',
      confirmLabel: 'Restore',
      icon: Icons.settings_backup_restore_rounded,
      destructive: false,
    );
    if (!ok) return;
    await service.restore(json);
    final backupSettings = json['settings'];
    if (backupSettings is Map) {
      await _settings.update((cur) {
        final merged = {...cur.toMap(), ...backupSettings.cast<String, Object?>()}
          ..['onboarded'] = true
          ..['lockEnabled'] = cur.lockEnabled
          ..['biometricsEnabled'] = cur.biometricsEnabled;
        return AppSettings.fromMap(merged);
      });
    }
    Haptics.success();
    _toast('Backup restored');
  });

  Future<void> _loadSample() => _run(() async {
    final ok = await confirmSheet(
      context,
      title: 'Load sample data?',
      message:
          'Adds three months of example transactions, budgets, bills and goals so you can explore. You can erase it later.',
      confirmLabel: 'Load',
      icon: Icons.auto_awesome_rounded,
      destructive: false,
    );
    if (!ok) return;
    await SampleData(ref.read(databaseProvider), ref.read(settingsProvider).currency).load();
    await ref.read(recurringRepositoryProvider).processDue(DateTime.now());
    _toast('Sample data loaded', icon: Icons.auto_awesome_rounded);
  });

  Future<void> _eraseAll() => _run(() async {
    final ok = await confirmSheet(
      context,
      title: 'Erase everything?',
      message:
          'All transactions, accounts, budgets, bills and goals will be deleted from this phone. This can\'t be undone. Make a backup first if you might need it.',
      confirmLabel: 'Erase',
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;
    final sure = await confirmSheet(
      context,
      title: 'Are you sure?',
      message: 'Last chance — your data will be gone for good.',
      confirmLabel: 'Yes, erase',
      icon: Icons.warning_amber_rounded,
    );
    if (!sure) return;
    await ref.read(databaseProvider).wipe();
    await ref.read(pinVaultProvider).clear();
    await _settings.update(
      (s) => s.copyWith(
        onboarded: false,
        lockEnabled: false,
        biometricsEnabled: false,
        defaultAccountId: () => null,
      ),
    );
    Haptics.heavy();
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final accounts = ref.watch(accountMapProvider);
    final txnCount = ref.watch(txnCountProvider).value ?? 0;
    String lockAfterLabel(int v) => switch (v) {
      0 => 'Immediately',
      30 => '30 seconds',
      60 => '1 minute',
      300 => '5 minutes',
      _ => '${v ~/ 60} minutes',
    };
    final time = TimeOfDay(
      hour: s.reminderMinutes ~/ 60,
      minute: s.reminderMinutes % 60,
    ).format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, 0),
                child: AppCard(
                  onTap: _editName,
                  child: Row(
                    children: [
                      const AppMark(size: 52),
                      const Gap(Insets.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name.isEmpty ? 'Add your name' : s.name,
                              style: context.text.titleMedium,
                            ),
                            const Gap(2),
                            Text(
                              'Private · offline · no account needed',
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.edit_outlined, size: 18, color: p.ink3),
                    ],
                  ),
                ),
              ),
              const GroupLabel('General'),
              _Group(
                children: [
                  _Row(
                    icon: Icons.payments_outlined,
                    title: 'Currency',
                    value: '${s.currency.code} · ${s.currency.symbol}',
                    onTap: _pickCurrency,
                  ),
                  _Row(
                    icon: Icons.pin_outlined,
                    title: 'Number format',
                    value: s.money.format(123456789),
                    onTap: _pickNumberStyle,
                  ),
                  _Row(
                    icon: Icons.event_repeat_rounded,
                    title: 'Month starts on',
                    value: s.monthStartDay == 1 ? '1st (calendar month)' : 'Day ${s.monthStartDay}',
                    onTap: _pickMonthStart,
                  ),
                  _Row(
                    icon: Icons.view_week_outlined,
                    title: 'Week starts on',
                    value: switch (s.weekStartDay) {
                      DateTime.sunday => 'Sunday',
                      DateTime.saturday => 'Saturday',
                      _ => 'Monday',
                    },
                    onTap: _pickWeekStart,
                  ),
                  _Row(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Default account',
                    value: accounts[s.defaultAccountId]?.name ?? 'First account',
                    onTap: _pickDefaultAccount,
                  ),
                ],
              ),
              const GroupLabel('Appearance'),
              _Group(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, Insets.sm),
                    child: SegmentedTabs<ThemeMode>(
                      values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
                      selected: s.themeMode,
                      labelOf: (m) => switch (m) {
                        ThemeMode.system => 'Auto',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      },
                      onChanged: (m) => _settings.update((x) => x.copyWith(themeMode: m)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.lg),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final a in AccentColor.values)
                          Pressable(
                            semanticLabel: a.label,
                            pressedScale: 0.85,
                            onTap: () => _settings.update((x) => x.copyWith(accent: a)),
                            child: AnimatedContainer(
                              duration: Motion.medium,
                              width: 38,
                              height: 38,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: s.accent == a
                                      ? (p.isDark ? a.dark : a.light)
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: p.isDark ? a.dark : a.light,
                                  shape: BoxShape.circle,
                                ),
                                child: s.accent == a
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: p.isDark ? Colors.black : Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Switch(
                    icon: Icons.vibration_rounded,
                    title: 'Haptic feedback',
                    value: s.haptics,
                    onChanged: (v) => _settings.update((x) => x.copyWith(haptics: v)),
                  ),
                ],
              ),
              const GroupLabel('Privacy & security'),
              _Group(
                children: [
                  _Switch(
                    icon: Icons.visibility_off_outlined,
                    title: 'Hide amounts',
                    subtitle: 'Mask balances until you tap the eye on Home',
                    value: s.hideAmounts,
                    onChanged: (v) => _settings.update((x) => x.copyWith(hideAmounts: v)),
                  ),
                  _Switch(
                    icon: Icons.lock_outline_rounded,
                    title: 'App lock',
                    subtitle: 'Require a PIN to open Spent',
                    value: s.lockEnabled,
                    onChanged: _toggleLock,
                  ),
                  if (s.lockEnabled && _bioAvailable)
                    _Switch(
                      icon: _bioLabel == 'Face ID'
                          ? Icons.face_retouching_natural_rounded
                          : Icons.fingerprint_rounded,
                      title: 'Unlock with $_bioLabel',
                      value: s.biometricsEnabled,
                      onChanged: _toggleBiometrics,
                    ),
                  if (s.lockEnabled) ...[
                    _Row(
                      icon: Icons.timer_outlined,
                      title: 'Lock when away',
                      value: lockAfterLabel(s.lockAfterSeconds),
                      onTap: _pickLockAfter,
                    ),
                    _Row(icon: Icons.password_rounded, title: 'Change PIN', onTap: _changePin),
                  ],
                ],
              ),
              const GroupLabel('Reminders'),
              _Group(
                children: [
                  _Switch(
                    icon: Icons.notifications_none_rounded,
                    title: 'Daily reminder',
                    subtitle: 'A nudge to log the day\'s spending',
                    value: s.dailyReminder,
                    onChanged: _toggleReminder,
                  ),
                  if (s.dailyReminder)
                    _Row(
                      icon: Icons.schedule_rounded,
                      title: 'Remind me at',
                      value: time,
                      onTap: _pickReminderTime,
                    ),
                  _Switch(
                    icon: Icons.receipt_outlined,
                    title: 'Bill reminders',
                    subtitle: 'On the morning a recurring payment is due',
                    value: s.billReminders,
                    onChanged: _toggleBills,
                  ),
                ],
              ),
              const GroupLabel('Manage'),
              _Group(
                children: [
                  _Row(
                    icon: Icons.account_balance_outlined,
                    title: 'Accounts',
                    onTap: () => context.push('/accounts'),
                  ),
                  _Row(
                    icon: Icons.category_outlined,
                    title: 'Categories',
                    onTap: () => context.push('/categories'),
                  ),
                  _Row(
                    icon: Icons.autorenew_rounded,
                    title: 'Recurring payments',
                    onTap: () => context.go('/plan?tab=bills'),
                  ),
                ],
              ),
              const GroupLabel('Your data'),
              _Group(
                children: [
                  _Row(
                    icon: Icons.table_view_outlined,
                    title: 'Export to CSV',
                    subtitle: 'Open in Excel or Sheets',
                    onTap: _exportCsv,
                  ),
                  _Row(
                    icon: Icons.save_alt_rounded,
                    title: 'Back up',
                    subtitle: 'Save everything to a file you keep',
                    onTap: _backupNow,
                  ),
                  _Row(
                    icon: Icons.settings_backup_restore_rounded,
                    title: 'Restore from backup',
                    onTap: _restore,
                  ),
                  if (txnCount == 0)
                    _Row(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Load sample data',
                      subtitle: 'Explore with example transactions',
                      onTap: _loadSample,
                    ),
                  _Row(
                    icon: Icons.delete_forever_outlined,
                    title: 'Erase all data',
                    destructive: true,
                    onTap: _eraseAll,
                  ),
                ],
              ),
              const Gap(Insets.xxl),
              Center(
                child: Column(
                  children: [
                    Text('Spent $appVersion', style: context.text.labelMedium),
                    const Gap(4),
                    Text(
                      'Everything stays on this device.\nNo account, no cloud, no tracking.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(color: p.ink3),
                    ),
                    const Gap(16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Made by Ketul with ', style: context.text.labelMedium),
                        const Icon(Icons.favorite, color: Colors.red, size: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: p.bg.withValues(alpha: 0.5),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    margin: const EdgeInsets.symmetric(horizontal: Insets.page),
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: Radii.card,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 58, color: context.palette.hairline),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class _Icon extends StatelessWidget {
  const _Icon(this.icon, {this.destructive = false});

  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 32,
      height: 32,
      decoration: ShapeDecoration(
        color: destructive ? p.negativeFill.withValues(alpha: 0.12) : p.surface2,
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Icon(icon, size: 18, color: destructive ? p.negative : p.ink2),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.lg, 12, Insets.md, 12),
        child: Row(
          children: [
            _Icon(icon, destructive: destructive),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.titleSmall?.copyWith(
                      color: destructive ? p.negative : p.ink,
                    ),
                  ),
                  if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
                ],
              ),
            ),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(color: p.ink2),
                ),
              ),
            if (!destructive) Icon(Icons.chevron_right_rounded, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      Haptics.selection();
      onChanged(!value);
    },
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 8, Insets.sm, 8),
      child: Row(
        children: [
          _Icon(icon),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              Haptics.selection();
              onChanged(v);
            },
          ),
        ],
      ),
    ),
  );
}
