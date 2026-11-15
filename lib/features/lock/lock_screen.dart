import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/services/security.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/features/lock/lock_controller.dart';
import 'package:spent/features/lock/pin_widgets.dart';
import 'package:spent/shared/widgets/motion.dart';

/// Covers the app until the PIN (or biometrics) unlocks it.
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(lockProvider);
    final obscured =
        ref.watch(obscureProvider) && ref.watch(settingsProvider.select((s) => s.lockEnabled));
    final Widget cover = locked
        ? const SizedBox.expand(key: ValueKey('locked'), child: LockScreen())
        : obscured
        ? const _PrivacyCover(key: ValueKey('cover'))
        : const SizedBox.shrink(key: ValueKey('open'));
    return Stack(
      children: [
        // Keep the app out of the accessibility tree and input while locked.
        ExcludeSemantics(
          excluding: locked,
          child: AbsorbPointer(absorbing: locked, child: child),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.slow),
            switchInCurve: Motion.emphasized,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(a), child: child),
            ),
            child: cover,
          ),
        ),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.palette.bg,
    child: const Center(child: AppMark(size: 72)),
  );
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  int _shake = 0;
  int _failures = 0;
  bool _error = false;
  bool _checking = false;
  DateTime? _lockedUntil;
  Timer? _ticker;
  bool _bioAvailable = false;
  String _bioLabel = 'Biometrics';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBiometrics());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _initBiometrics() async {
    if (!ref.read(settingsProvider).biometricsEnabled) return;
    final bio = ref.read(biometricsProvider);
    final available = await bio.available();
    final label = await bio.label();
    if (!mounted) return;
    setState(() {
      _bioAvailable = available;
      _bioLabel = label;
    });
    if (available) await _biometric();
  }

  Future<void> _biometric() async {
    final ok = await ref
        .read(lockProvider.notifier)
        .withoutLock(() => ref.read(biometricsProvider).authenticate('Unlock Spent'));
    if (ok && mounted) _unlock();
  }

  void _unlock() {
    Haptics.success();
    ref.read(lockProvider.notifier).unlock();
  }

  int get _secondsLeft {
    final until = _lockedUntil;
    if (until == null) return 0;
    return until.difference(DateTime.now()).inSeconds.clamp(0, 9999) + 1;
  }

  bool get _lockedOut => _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  Future<void> _digit(int d) async {
    if (_checking || _lockedOut || _pin.length >= pinLength) return;
    setState(() {
      _pin += '$d';
      _error = false;
    });
    if (_pin.length < pinLength) return;
    setState(() => _checking = true);
    final ok = await ref.read(pinVaultProvider).verify(_pin);
    if (!mounted) return;
    if (ok) {
      _unlock();
      return;
    }
    Haptics.error();
    _failures++;
    setState(() {
      _checking = false;
      _error = true;
      _shake++;
      _pin = '';
      if (_failures >= 5) {
        // 30s after five misses, then longer each further miss.
        _lockedUntil = DateTime.now().add(Duration(seconds: 30 * (_failures - 4)));
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          if (!_lockedOut) t.cancel();
          setState(() {});
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = _lockedOut
        ? 'Too many attempts. Try again in ${_secondsLeft}s.'
        : _error
        ? 'Wrong PIN. Try again.'
        : 'Enter your PIN';
    return Material(
      color: p.bg,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            const FadeSlideIn(child: AppMark(size: 64)),
            const Gap(Insets.xl),
            Text('Spent is locked', style: context.text.headlineSmall),
            const Gap(Insets.sm),
            AnimatedSwitcher(
              duration: Motion.fast,
              child: Text(
                status,
                key: ValueKey(status),
                style: context.text.bodyMedium?.copyWith(
                  color: _error || _lockedOut ? p.negative : p.ink2,
                ),
              ),
            ),
            const Gap(Insets.xxl),
            Shake(
              trigger: _shake,
              child: PinDots(filled: _pin.length, error: _error),
            ),
            const Spacer(flex: 2),
            PinPad(
              enabled: !_lockedOut && !_checking,
              onDigit: _digit,
              onBackspace: () {
                if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
              },
              leading: _bioAvailable
                  ? Semantics(
                      button: true,
                      label: 'Unlock with $_bioLabel',
                      child: IconButton(
                        onPressed: _biometric,
                        icon: Icon(
                          _bioLabel == 'Face ID'
                              ? Icons.face_retouching_natural_rounded
                              : Icons.fingerprint_rounded,
                          size: 32,
                          color: p.ink,
                        ),
                      ),
                    )
                  : null,
            ),
            const Gap(Insets.xxl),
          ],
        ),
      ),
    );
  }
}

/// Create a new PIN (enter + confirm) or verify the current one.
/// Resolves to true on success.
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen.create({super.key}) : verify = false;
  const PinScreen.verify({super.key}) : verify = true;

  final bool verify;

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  String _pin = '';
  String? _first;
  bool _error = false;
  int _shake = 0;
  bool _busy = false;

  String get _title {
    if (widget.verify) return 'Enter your PIN';
    return _first == null ? 'Create a PIN' : 'Confirm your PIN';
  }

  String get _subtitle {
    if (_error) {
      return widget.verify || _first == null
          ? 'Wrong PIN. Try again.'
          : 'PINs didn\'t match. Start again.';
    }
    if (widget.verify) return 'Confirm it\'s you to change security settings.';
    return _first == null ? 'Four digits to unlock Spent.' : 'Enter the same four digits again.';
  }

  Future<void> _digit(int d) async {
    if (_busy || _pin.length >= pinLength) return;
    setState(() {
      _pin += '$d';
      _error = false;
    });
    if (_pin.length < pinLength) return;
    final vault = ref.read(pinVaultProvider);
    if (widget.verify) {
      setState(() => _busy = true);
      final ok = await vault.verify(_pin);
      if (!mounted) return;
      if (ok) {
        Haptics.success();
        Navigator.pop(context, true);
      } else {
        _fail(resetFirst: false);
      }
      return;
    }
    if (_first == null) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      setState(() {
        _first = _pin;
        _pin = '';
      });
      return;
    }
    if (_pin == _first) {
      setState(() => _busy = true);
      await vault.setPin(_pin);
      Haptics.success();
      if (mounted) Navigator.pop(context, true);
    } else {
      _fail(resetFirst: true);
    }
  }

  void _fail({required bool resetFirst}) {
    Haptics.error();
    setState(() {
      _busy = false;
      _error = true;
      _shake++;
      _pin = '';
      if (resetFirst) _first = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: CloseButton(onPressed: () => Navigator.pop(context, false))),
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              const Spacer(),
              AnimatedSwitcher(
                duration: Motion.medium,
                child: Text(_title, key: ValueKey(_title), style: context.text.headlineSmall),
              ),
              const Gap(Insets.sm),
              Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(color: _error ? p.negative : p.ink2),
              ),
              const Gap(Insets.xxl),
              Shake(
                trigger: _shake,
                child: PinDots(filled: _pin.length, error: _error),
              ),
              const Spacer(),
              PinPad(
                enabled: !_busy,
                onDigit: _digit,
                onBackspace: () {
                  if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                },
              ),
              const Gap(Insets.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
