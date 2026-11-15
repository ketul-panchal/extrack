import 'dart:async';

import 'package:flutter/services.dart';

/// Haptic feedback that respects the user's setting.
abstract final class Haptics {
  static bool enabled = true;

  static void selection() {
    if (enabled) unawaited(HapticFeedback.selectionClick());
  }

  static void light() {
    if (enabled) unawaited(HapticFeedback.lightImpact());
  }

  static void medium() {
    if (enabled) unawaited(HapticFeedback.mediumImpact());
  }

  static void heavy() {
    if (enabled) unawaited(HapticFeedback.heavyImpact());
  }

  static void success() => medium();

  static void error() {
    if (!enabled) return;
    unawaited(HapticFeedback.heavyImpact());
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (enabled) unawaited(HapticFeedback.mediumImpact());
    });
  }
}
