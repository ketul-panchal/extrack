import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/pressable.dart';

enum ButtonVariant { primary, accent, secondary, ghost, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = ButtonVariant.primary,
    this.expand = true,
    this.height = 54,
    this.loading = false,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.height = 54,
    this.loading = false,
  }) : variant = ButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.height = 44,
    this.loading = false,
  }) : variant = ButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonVariant variant;
  final bool expand;
  final double height;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !loading;
    final (bg, fg) = switch (variant) {
      ButtonVariant.primary => (p.primary, p.onPrimary),
      ButtonVariant.accent => (p.accent, p.onAccent),
      ButtonVariant.secondary => (p.surface2, p.ink),
      ButtonVariant.ghost => (Colors.transparent, p.ink),
      ButtonVariant.danger => (p.negativeFill, Colors.white),
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if ((icon != null || loading) && label.isNotEmpty) const Gap(Insets.sm),
        if (label.isNotEmpty)
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelLarge?.copyWith(color: fg),
            ),
          ),
      ],
    );
    return AnimatedOpacity(
      opacity: enabled || loading ? 1 : 0.4,
      duration: Motion.fast,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        pressedScale: 0.96,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: Motion.medium,
          curve: Motion.standard,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: variant == ButtonVariant.ghost ? 12 : 22),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(height / 2)),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// Round icon button on a quiet fill.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 21,
    this.tooltip,
    this.filled = true,
    this.color,
    this.background,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final bool filled;
  final Color? color;
  final Color? background;

  /// Small accent dot in the corner (e.g. active filters).
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button = Pressable(
      onTap: onPressed,
      pressedScale: 0.9,
      semanticLabel: tooltip,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.35 : 1,
        duration: Motion.fast,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: filled ? (background ?? p.surface2) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: iconSize, color: color ?? p.ink),
              if (badge)
                Positioned(
                  top: size * 0.2,
                  right: size * 0.2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: filled ? (background ?? p.surface2) : p.bg,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// Pill-shaped choice chip: ink when selected, quiet fill otherwise.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? leading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.onPrimary : p.ink;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.95,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.standard,
        height: dense ? 34 : 40,
        padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14),
        decoration: BoxDecoration(
          color: selected ? p.primary : p.surface2,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const Gap(6)],
            if (icon != null) ...[Icon(icon, size: 17, color: fg), const Gap(6)],
            AnimatedDefaultTextStyle(
              duration: Motion.medium,
              style: (dense ? context.text.labelMedium : context.text.titleSmall)!.copyWith(
                color: fg,
              ),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
