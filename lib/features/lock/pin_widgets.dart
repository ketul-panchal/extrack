import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/brand_logo.dart';
import 'package:spent/shared/widgets/pressable.dart';

const pinLength = 4;

/// Four dots that fill as digits are entered.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, this.error = false});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < pinLength; i++)
          AnimatedContainer(
            duration: Motion.fast,
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: i < filled ? 16 : 14,
            height: i < filled ? 16 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: error ? p.negativeFill : (i < filled ? p.ink : Colors.transparent),
              border: Border.all(color: error ? p.negativeFill : p.ink3, width: 1.6),
            ),
          ),
      ],
    );
  }
}

/// Round number keys for PIN entry. [leading] fills the bottom-left slot
/// (biometrics), backspace sits bottom-right.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.leading,
    this.enabled = true,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final Widget? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget key(int d) => _RoundKey(
      onTap: enabled ? () => onDigit(d) : null,
      child: Text('$d', style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
    );
    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: keys),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([key(1), key(2), key(3)]),
          row([key(4), key(5), key(6)]),
          row([key(7), key(8), key(9)]),
          row([
            SizedBox.square(dimension: 76, child: leading),
            key(0),
            _RoundKey(
              onTap: enabled ? onBackspace : null,
              filled: false,
              child: Icon(Icons.backspace_outlined, color: p.ink2),
            ),
          ]),
        ],
      ),
    );
  }
}

class _RoundKey extends StatelessWidget {
  const _RoundKey({required this.child, required this.onTap, this.filled = true});

  final Widget child;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      haptic: false,
      pressedScale: 0.88,
      onTap: onTap == null
          ? null
          : () {
              Haptics.selection();
              onTap!();
            },
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: filled ? p.surface2 : Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// The app's logo tile (same artwork as the launcher icon).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(size * 0.27),
          side: p.isDark ? BorderSide(color: p.hairline) : BorderSide.none,
        ),
        shadows: p.isDark
            ? null
            : [
                BoxShadow(
                  color: p.shadow.withValues(alpha: 0.22),
                  blurRadius: size * 0.3,
                  offset: Offset(0, size * 0.12),
                ),
              ],
      ),
      child: SpentLogo(size: size),
    );
  }
}
