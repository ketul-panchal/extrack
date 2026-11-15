import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/pressable.dart';

/// Large title at the top of a tab, with optional actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(Insets.page, top + Insets.md, Insets.page - 4, Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle!, style: context.text.labelMedium),
                  const Gap(2),
                ],
                Text(
                  title,
                  style: context.text.headlineLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          for (final a in actions) ...[const Gap(Insets.sm), a],
        ],
      ),
    );
  }
}

/// Section title with an optional "See all" style action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(Insets.page, Insets.xl, Insets.page, Insets.md),
    this.trailing,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleLarge)),
          ?trailing,
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(action!, style: context.text.labelMedium?.copyWith(color: p.ink2)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: p.ink3),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Friendly placeholder for empty lists, with an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = compact ? 64.0 : 84.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Insets.xxxl, vertical: compact ? Insets.xl : 48),
      child: FadeSlideIn(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Float(
              child: Container(
                width: size,
                height: size,
                decoration: ShapeDecoration(
                  color: p.accentSoft,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(size * 0.36),
                  ),
                ),
                child: Icon(icon, size: size * 0.44, color: p.accentText),
              ),
            ),
            Gap(compact ? Insets.lg : Insets.xxl),
            Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
            const Gap(Insets.sm),
            Text(
              message,
              style: context.text.bodyMedium?.copyWith(color: p.ink2),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const Gap(Insets.xl),
              AppButton(label: actionLabel!, onPressed: onAction, expand: false, height: 46),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small uppercase-free label above a group of rows.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(Insets.page, Insets.xl, Insets.page, Insets.sm),
    child: Text(text, style: context.text.labelMedium?.copyWith(color: context.palette.ink3)),
  );
}
