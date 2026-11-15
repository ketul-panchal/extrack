import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/settings/stores.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/time/periods.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.onboarded = false,
    this.name = '',
    this.currencyCode = 'USD',
    this.numberStyle = NumberStyle.western,
    this.themeMode = ThemeMode.system,
    this.accent = AccentColor.emerald,
    this.monthStartDay = 1,
    this.weekStartDay = DateTime.monday,
    this.defaultAccountId,
    this.haptics = true,
    this.hideAmounts = false,
    this.lockEnabled = false,
    this.biometricsEnabled = false,
    this.lockAfterSeconds = 0,
    this.dailyReminder = false,
    this.reminderMinutes = 21 * 60,
    this.billReminders = true,
  });

  final bool onboarded;

  /// Optional first name for the greeting.
  final String name;
  final String currencyCode;
  final NumberStyle numberStyle;
  final ThemeMode themeMode;
  final AccentColor accent;

  /// Day of month budgets reset (1–28), e.g. payday.
  final int monthStartDay;
  final int weekStartDay;
  final int? defaultAccountId;
  final bool haptics;

  /// Privacy mode: masks every amount until tapped off.
  final bool hideAmounts;
  final bool lockEnabled;
  final bool biometricsEnabled;

  /// Lock again after the app has been in the background this long.
  final int lockAfterSeconds;
  final bool dailyReminder;

  /// Minutes after midnight for the daily reminder.
  final int reminderMinutes;
  final bool billReminders;

  Currency get currency => Currency.byCode(currencyCode);
  MoneyFormat get money => MoneyFormat(currency, numberStyle);
  PeriodCalculator get periods =>
      PeriodCalculator(monthStartDay: monthStartDay, weekStartDay: weekStartDay);

  AppSettings copyWith({
    bool? onboarded,
    String? name,
    String? currencyCode,
    NumberStyle? numberStyle,
    ThemeMode? themeMode,
    AccentColor? accent,
    int? monthStartDay,
    int? weekStartDay,
    int? Function()? defaultAccountId,
    bool? haptics,
    bool? hideAmounts,
    bool? lockEnabled,
    bool? biometricsEnabled,
    int? lockAfterSeconds,
    bool? dailyReminder,
    int? reminderMinutes,
    bool? billReminders,
  }) => AppSettings(
    onboarded: onboarded ?? this.onboarded,
    name: name ?? this.name,
    currencyCode: currencyCode ?? this.currencyCode,
    numberStyle: numberStyle ?? this.numberStyle,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    monthStartDay: monthStartDay ?? this.monthStartDay,
    weekStartDay: weekStartDay ?? this.weekStartDay,
    defaultAccountId: defaultAccountId != null ? defaultAccountId() : this.defaultAccountId,
    haptics: haptics ?? this.haptics,
    hideAmounts: hideAmounts ?? this.hideAmounts,
    lockEnabled: lockEnabled ?? this.lockEnabled,
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
    dailyReminder: dailyReminder ?? this.dailyReminder,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    billReminders: billReminders ?? this.billReminders,
  );

  /// Flat map of every setting, as persisted.
  Map<String, Object?> toMap() => {
    'onboarded': onboarded,
    'name': name,
    'currencyCode': currencyCode,
    'numberStyle': numberStyle.name,
    'themeMode': themeMode.name,
    'accent': accent.name,
    'monthStartDay': monthStartDay,
    'weekStartDay': weekStartDay,
    'defaultAccountId': defaultAccountId,
    'haptics': haptics,
    'hideAmounts': hideAmounts,
    'lockEnabled': lockEnabled,
    'biometricsEnabled': biometricsEnabled,
    'lockAfterSeconds': lockAfterSeconds,
    'dailyReminder': dailyReminder,
    'reminderMinutes': reminderMinutes,
    'billReminders': billReminders,
  };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  factory AppSettings.fromMap(Map<String, Object?> m) {
    const d = AppSettings();
    T read<T>(String k, T fallback) => m[k] is T ? m[k] as T : fallback;
    return AppSettings(
      onboarded: read('onboarded', d.onboarded),
      name: read('name', d.name),
      currencyCode: read('currencyCode', d.currencyCode),
      numberStyle: _enum(NumberStyle.values, m['numberStyle'], d.numberStyle),
      themeMode: _enum(ThemeMode.values, m['themeMode'], d.themeMode),
      accent: _enum(AccentColor.values, m['accent'], d.accent),
      monthStartDay: read<int>('monthStartDay', d.monthStartDay).clamp(1, 28),
      weekStartDay: read<int>('weekStartDay', d.weekStartDay).clamp(1, 7),
      defaultAccountId: m['defaultAccountId'] is int ? m['defaultAccountId'] as int : null,
      haptics: read('haptics', d.haptics),
      hideAmounts: read('hideAmounts', d.hideAmounts),
      lockEnabled: read('lockEnabled', d.lockEnabled),
      biometricsEnabled: read('biometricsEnabled', d.biometricsEnabled),
      lockAfterSeconds: read('lockAfterSeconds', d.lockAfterSeconds),
      dailyReminder: read('dailyReminder', d.dailyReminder),
      reminderMinutes: read('reminderMinutes', d.reminderMinutes),
      billReminders: read('billReminders', d.billReminders),
    );
  }

  /// Settings worth carrying across a backup/restore (no security state).
  Map<String, Object?> toBackupJson() => toMap()
    ..remove('lockEnabled')
    ..remove('biometricsEnabled')
    ..remove('onboarded');
}

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError('keyValueStoreProvider must be overridden'),
);

final secretStoreProvider = Provider<SecretStore>((ref) => const DeviceSecretStore());

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  static const _prefix = 'settings.';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  AppSettings build() {
    final store = ref.watch(keyValueStoreProvider);
    final map = <String, Object?>{};
    // Read each key with the getter matching its default's type; the only
    // nullable setting (defaultAccountId) is an int.
    for (final e in const AppSettings().toMap().entries) {
      final key = '$_prefix${e.key}';
      map[e.key] = switch (e.value) {
        bool() => store.getBool(key),
        String() => store.getString(key),
        _ => store.getInt(key),
      };
    }
    return AppSettings.fromMap(map);
  }

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    final before = state.toMap();
    state = change(state);
    final after = state.toMap();
    for (final entry in after.entries) {
      if (before[entry.key] == entry.value) continue;
      final key = '$_prefix${entry.key}';
      switch (entry.value) {
        case null:
          await _store.remove(key);
        case final bool v:
          await _store.setBool(key, v);
        case final int v:
          await _store.setInt(key, v);
        case final String v:
          await _store.setString(key, v);
      }
    }
  }
}

/// Fine-grained selectors so widgets rebuild only for what they use.
final moneyFormatProvider = Provider<MoneyFormat>((ref) {
  final code = ref.watch(settingsProvider.select((s) => s.currencyCode));
  final style = ref.watch(settingsProvider.select((s) => s.numberStyle));
  return MoneyFormat(Currency.byCode(code), style);
});

final periodCalculatorProvider = Provider<PeriodCalculator>((ref) {
  final start = ref.watch(settingsProvider.select((s) => s.monthStartDay));
  final week = ref.watch(settingsProvider.select((s) => s.weekStartDay));
  return PeriodCalculator(monthStartDay: start, weekStartDay: week);
});

final hideAmountsProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.hideAmounts)),
);
