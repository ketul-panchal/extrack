import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/sheets.dart';

/// Space to leave under tab content. The shell's Scaffold uses extendBody,
/// so the bottom padding already includes the floating nav bar.
double navBarClearance(BuildContext context) => MediaQuery.paddingOf(context).bottom + 24;

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(int index) {
    Haptics.selection();
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: navigationShell,
    bottomNavigationBar: _FloatingNavBar(
      index: navigationShell.currentIndex,
      onTap: _go,
      onAdd: () => context.push('/txn/new'),
      onAddLong: () => _quickAdd(context),
    ),
  );

  Future<void> _quickAdd(BuildContext context) async {
    final kind = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Add'),
          OptionRow(
            leading: const Icon(Icons.north_east_rounded),
            title: 'Expense',
            subtitle: 'Money you spent',
            onTap: () => Navigator.pop(ctx, 'expense'),
          ),
          OptionRow(
            leading: const Icon(Icons.south_west_rounded),
            title: 'Income',
            subtitle: 'Money you received',
            onTap: () => Navigator.pop(ctx, 'income'),
          ),
          OptionRow(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: 'Transfer',
            subtitle: 'Between your accounts',
            onTap: () => Navigator.pop(ctx, 'transfer'),
          ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (kind != null && context.mounted) unawaited(context.push('/txn/new?kind=$kind'));
  }
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.onTap,
    required this.onAdd,
    required this.onAddLong,
  });

  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  final VoidCallback onAddLong;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
    (Icons.donut_large_rounded, Icons.donut_large_rounded, 'Plan'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Insights'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget item(int i) {
      final (icon, active, label) = _items[i];
      final selected = i == index;
      return Expanded(
        child: Pressable(
          onTap: () => onTap(i),
          haptic: false,
          pressedScale: 0.9,
          semanticLabel: label,
          child: SizedBox(
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: Motion.fast,
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: Icon(
                    selected ? active : icon,
                    key: ValueKey(selected),
                    size: 24,
                    color: selected ? p.ink : p.ink3,
                  ),
                ),
                const Gap(3),
                AnimatedDefaultTextStyle(
                  duration: Motion.medium,
                  style: context.text.labelSmall!.copyWith(
                    color: selected ? p.ink : p.ink3,
                    letterSpacing: 0.1,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, bottom > 0 ? bottom : Insets.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: p.floatingShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: (p.isDark ? p.surface2 : p.surface).withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: p.hairline.withValues(alpha: p.isDark ? 1 : 0.6)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  item(0),
                  item(1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Pressable(
                      onTap: onAdd,
                      onLongPress: onAddLong,
                      pressedScale: 0.88,
                      semanticLabel: 'Add transaction',
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: p.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: p.shadow.withValues(alpha: p.isDark ? 0.4 : 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(Icons.add_rounded, color: p.onPrimary, size: 28),
                      ),
                    ),
                  ),
                  item(2),
                  item(3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps every tab alive and cross-fades between them (fade-through).
class BranchSwitcher extends StatelessWidget {
  const BranchSwitcher({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (var i = 0; i < children.length; i++) _Branch(active: i == index, child: children[i]),
    ],
  );
}

class _Branch extends StatefulWidget {
  const _Branch({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 120),
    value: widget.active ? 1 : 0,
  );

  Timer? _delay;

  @override
  void didUpdateWidget(_Branch old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      _delay?.cancel();
      if (widget.active) {
        // Wait for the outgoing tab to fade first.
        _c.value = 0;
        _delay = Timer(const Duration(milliseconds: 70), () {
          if (mounted && widget.active) _c.forward();
        });
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = reduced ? (widget.active ? 1.0 : 0.0) : _c.value;
        final hidden = v == 0 && !widget.active;
        return Offstage(
          offstage: hidden,
          child: TickerMode(
            enabled: widget.active,
            child: IgnorePointer(
              ignoring: !widget.active,
              child: Opacity(
                opacity: Curves.easeOut.transform(v),
                child: Transform.translate(
                  offset: Offset(0, (1 - Motion.emphasized.transform(v)) * 10),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
