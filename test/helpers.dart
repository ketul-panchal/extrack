import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/services/notifications.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/settings/stores.dart';
import 'package:spent/data/providers.dart';

AppDatabase memoryDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Notifications talk to the OS; tests don't.
class FakeNotificationService extends NotificationService {
  int syncs = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> sync({
    required AppSettings settings,
    required List<RecurringRule> rules,
    required Map<int, Category> categories,
    required MoneyFormat money,
  }) async => syncs++;
}

/// Overrides every platform-backed provider with an in-memory fake.
List<Override> testOverrides({
  required AppDatabase db,
  MemoryKeyValueStore? store,
  MemorySecretStore? secrets,
}) => [
  databaseProvider.overrideWithValue(db),
  keyValueStoreProvider.overrideWithValue(store ?? MemoryKeyValueStore()),
  secretStoreProvider.overrideWithValue(secrets ?? MemorySecretStore()),
  notificationServiceProvider.overrideWithValue(FakeNotificationService()),
];
