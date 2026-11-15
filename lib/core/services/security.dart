import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/settings/stores.dart';

/// Stores the app-lock PIN as a salted, iterated SHA-256 hash in the
/// Keychain / Keystore. The PIN itself is never stored.
class PinVault {
  PinVault(this._store);

  final SecretStore _store;

  static const _hashKey = 'pin.hash';
  static const _saltKey = 'pin.salt';
  static const _rounds = 20000;

  Future<bool> hasPin() async => (await _store.read(_hashKey)) != null;

  Future<void> setPin(String pin) async {
    final random = math.Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
    final hash = await Isolate.run(() => _hash(pin, salt));
    await _store.write(_saltKey, salt);
    await _store.write(_hashKey, hash);
  }

  Future<bool> verify(String pin) async {
    final salt = await _store.read(_saltKey);
    final hash = await _store.read(_hashKey);
    if (salt == null || hash == null) return false;
    final candidate = await Isolate.run(() => _hash(pin, salt));
    return _constantTimeEquals(candidate, hash);
  }

  Future<void> clear() async {
    await _store.delete(_hashKey);
    await _store.delete(_saltKey);
  }

  static String _hash(String pin, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$pin')).bytes;
    final saltBytes = utf8.encode(salt);
    for (var i = 0; i < _rounds; i++) {
      digest = sha256.convert([...digest, ...saltBytes]).bytes;
    }
    return base64Encode(digest);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Face ID / fingerprint, when the device has it enrolled.
class Biometrics {
  final _auth = LocalAuthentication();

  Future<bool> available() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on Object {
      return false;
    }
  }

  /// Short label for buttons: "Face ID", "Fingerprint" or "Biometrics".
  Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
    } on Object {
      // Fall through to the generic label.
    }
    return 'Biometrics';
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }
}

final pinVaultProvider = Provider<PinVault>((ref) => PinVault(ref.watch(secretStoreProvider)));
final biometricsProvider = Provider<Biometrics>((ref) => Biometrics());
