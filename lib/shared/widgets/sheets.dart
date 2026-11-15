import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/buttons.dart';

/// Opens a rounded bottom sheet that grows with its content, stays above the
/// keyboard and never exceeds ~92% of the screen.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final p = context.palette;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: p.surface,
    sheetAnimationStyle: const AnimationStyle(
      duration: Motion.slow,
      reverseDuration: Motion.medium,
      curve: Motion.emphasized,
    ),
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Handle(),
              Flexible(child: SafeArea(top: false, child: builder(ctx))),
            ],
          ),
        ),
      );
    },
  );
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Container(
      width: 38,
      height: 4.5,
      decoration: BoxDecoration(
        color: context.palette.ink3.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

/// Title row for sheets.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page - 4, Insets.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.headlineSmall),
              if (subtitle != null) ...[
                const Gap(2),
                Text(
                  subtitle!,
                  style: context.text.bodyMedium?.copyWith(color: context.palette.ink2),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Asks before something irreversible. Resolves to true on confirm.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  IconData icon = Icons.delete_outline_rounded,
  bool destructive = true,
}) async {
  final result = await showAppSheet<bool>(
    context,
    builder: (ctx) {
      final p = ctx.palette;
      final tint = destructive ? p.negativeFill : p.accent;
      return Padding(
        padding: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: tint, size: 28),
            ),
            const Gap(Insets.lg),
            Text(title, style: ctx.text.headlineSmall, textAlign: TextAlign.center),
            const Gap(Insets.sm),
            Text(
              message,
              style: ctx.text.bodyMedium?.copyWith(color: p.ink2),
              textAlign: TextAlign.center,
            ),
            const Gap(Insets.xxl),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const Gap(Insets.md),
                Expanded(
                  child: AppButton(
                    label: confirmLabel,
                    variant: destructive ? ButtonVariant.danger : ButtonVariant.primary,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

/// A tappable row used inside sheets and settings.
class OptionRow extends StatelessWidget {
  const OptionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.page, vertical: 13),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const Gap(14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.titleSmall?.copyWith(
                      color: destructive ? p.negative : p.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const Gap(2),
                    Text(subtitle!, style: context.text.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (selected)
              Icon(Icons.check_rounded, color: p.accentText, size: 22),
          ],
        ),
      ),
    );
  }
}
