import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spent/core/settings/settings.dart';

/// Whether the app is currently locked behind the PIN.
final lockProvider = NotifierProvider<LockController, bool>(LockController.new);

class LockController extends Notifier<bool> {
  DateTime? _backgroundedAt;
  int _suspended = 0;

  /// Locked on a cold start when app lock is on.
  @override
  bool build() => ref.read(settingsProvider).lockEnabled;

  void onBackground() {
    if (_suspended == 0) _backgroundedAt ??= clock.now();
  }

  void onForeground() {
    final at = _backgroundedAt;
    _backgroundedAt = null;
    final s = ref.read(settingsProvider);
    if (!s.lockEnabled || _suspended > 0 || at == null) return;
    if (clock.now().difference(at).inSeconds >= s.lockAfterSeconds) state = true;
  }

  void unlock() => state = false;

  void lockNow() {
    if (ref.read(settingsProvider).lockEnabled) state = true;
  }

  /// Runs [action] (a file picker, a share sheet, a biometric prompt) without
  /// the brief trip to the background locking the app.
  Future<T> withoutLock<T>(Future<T> Function() action) async {
    _suspended++;
    try {
      return await action();
    } finally {
      _suspended--;
      _backgroundedAt = null;
    }
  }
}

/// True while the app is inactive/backgrounded and its content should be
/// hidden from the app switcher.
final obscureProvider = NotifierProvider<ObscureController, bool>(ObscureController.new);

class ObscureController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) {
    if (v != state) state = v;
  }
}
