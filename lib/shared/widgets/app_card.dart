import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/pressable.dart';

/// A surface card: white with a soft shadow in light mode, a quiet raised
/// surface with a hairline in dark mode.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.onTap,
    this.onLongPress,
    this.color,
    this.radius = Radii.lg,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: color == null ? p.cardShadow : null,
        border: p.isDark && color == null ? Border.all(color: p.hairline) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap != null || onLongPress != null) {
      card = Pressable(onTap: onTap, onLongPress: onLongPress, pressedScale: 0.98, child: card);
    }
    if (margin != null) card = Padding(padding: margin!, child: card);
    return card;
  }
}
