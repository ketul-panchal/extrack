import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/app_icons.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';

/// A category/account/goal icon in a tinted squircle.
class EntityIcon extends StatelessWidget {
  const EntityIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 42,
    this.filled = false,
  });

  final String icon;

  /// Stored entity color (light value); resolved for the current theme.
  final int color;
  final double size;

  /// Solid color with a white glyph, for selected states.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = p.entity(color);
    return AnimatedContainer(
      duration: Motion.medium,
      curve: Motion.standard,
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: filled ? c : p.entitySoft(color),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(size * 0.34)),
      ),
      alignment: Alignment.center,
      child: Icon(AppIcons.of(icon), size: size * 0.5, color: filled ? Colors.white : c),
    );
  }
}

/// A small filled dot in an entity color, for legends.
class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
