import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synchronous reads, async writes. Backed by shared preferences on device
/// and by a map in tests.
abstract interface class KeyValueStore {
  String? getString(String key);
  int? getInt(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> setBool(String key, bool value);
  Future<void> remove(String key);
}

class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore._(this._prefs);

  final SharedPreferencesWithCache _prefs;

  static Future<PrefsKeyValueStore> open() async => PrefsKeyValueStore._(
    await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    ),
  );

  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  int? getInt(String key) => _prefs.getInt(key);
  @override
  bool? getBool(String key) => _prefs.getBool(key);
  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

class MemoryKeyValueStore implements KeyValueStore {
  MemoryKeyValueStore([Map<String, Object>? values]) : values = values ?? {};

  final Map<String, Object> values;

  @override
  String? getString(String key) => values[key] as String?;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<void> setInt(String key, int value) async => values[key] = value;
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Keychain / Keystore-backed storage for the app-lock PIN hash.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecretStore implements SecretStore {
  const DeviceSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}
