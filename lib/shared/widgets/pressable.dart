import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/tokens.dart';

/// Scales down while pressed and springs back on release — the app's single
/// tactile response, used instead of ink splashes on cards and buttons.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.haptic = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduced = Motion.reduced(context);
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: enabled ? () => _set(false) : null,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.haptic) Haptics.selection();
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  _set(false);
                  Haptics.medium();
                  widget.onLongPress!();
                },
          child: AnimatedScale(
            scale: _down && !reduced ? widget.pressedScale : 1,
            duration: _down ? Motion.instant : Motion.medium,
            curve: _down ? Curves.easeOut : Curves.easeOutBack,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
