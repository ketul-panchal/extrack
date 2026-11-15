import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';

enum ToastTone { neutral, success, warning, danger }

/// Small floating messages with an optional action ("Undo"). One at a time;
/// a new toast replaces the current one. Swipe down to dismiss.
abstract final class AppToast {
  static OverlayEntry? _entry;
  static GlobalKey<_ToastViewState>? _key;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    ToastTone tone = ToastTone.neutral,
    Duration duration = const Duration(seconds: 4),
    bool aboveNavBar = false,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _removeNow();
    final key = GlobalKey<_ToastViewState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        key: key,
        message: message,
        icon: icon,
        tone: tone,
        actionLabel: actionLabel,
        aboveNavBar: aboveNavBar,
        onAction: onAction == null
            ? null
            : () {
                Haptics.light();
                onAction();
                key.currentState?.dismiss();
              },
        onGone: () {
          if (identical(_entry, entry)) {
            _entry = null;
            _key = null;
          }
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _entry = entry;
    _key = key;
    overlay.insert(entry);
    _timer = Timer(duration, () => key.currentState?.dismiss());
  }

  static void hide() => _key?.currentState?.dismiss();

  static void _removeNow() {
    _timer?.cancel();
    final e = _entry;
    _entry = null;
    _key = null;
    if (e != null && e.mounted) e.remove();
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    super.key,
    required this.message,
    required this.icon,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.onGone,
    required this.aboveNavBar,
  });

  final String message;
  final IconData? icon;
  final ToastTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onGone;
  final bool aboveNavBar;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.slow,
    reverseDuration: Motion.medium,
  )..forward();
  bool _leaving = false;
  double _drag = 0;

  void dismiss() {
    if (_leaving || !mounted) return;
    _leaving = true;
    _c.reverse().whenComplete(widget.onGone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final media = MediaQuery.of(context);
    final iconColor = switch (widget.tone) {
      ToastTone.neutral => p.isDark ? p.ink : p.surface,
      ToastTone.success => p.accent,
      ToastTone.warning => p.warningFill,
      ToastTone.danger => p.negativeFill,
    };
    final bg = p.isDark ? p.surface3 : p.ink;
    final fg = p.isDark ? p.ink : p.surface;
    final bottom = media.padding.bottom + (widget.aboveNavBar ? 96 : 20) + media.viewInsets.bottom;
    final curved = CurvedAnimation(parent: _c, curve: Motion.emphasized, reverseCurve: Motion.exit);
    return Positioned(
      left: Insets.lg,
      right: Insets.lg,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Opacity(
          opacity: curved.value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - curved.value) * 40 + _drag),
            child: Transform.scale(scale: 0.94 + 0.06 * curved.value, child: child),
          ),
        ),
        child: GestureDetector(
          onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(0, 200)),
          onVerticalDragEnd: (_) => _drag > 24 ? dismiss() : setState(() => _drag = 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(18),
                boxShadow: p.floatingShadow,
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: iconColor, size: 20),
                    const Gap(Insets.md),
                  ],
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        widget.message,
                        style: context.text.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (widget.actionLabel != null)
                    TextButton(
                      onPressed: widget.onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: p.isDark ? p.accent : p.accent,
                        textStyle: context.text.labelLarge,
                      ),
                      child: Text(widget.actionLabel!),
                    )
                  else
                    const Gap(Insets.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
