import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/models.dart';
import 'package:spent/features/transactions/txn_actions.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/pressable.dart';

final int _slate = EntityColors.slate.light.toARGB32();

/// One transaction: icon, what, where, how much.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.view, this.onTap, this.showDate = false});

  final TxnView view;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = view.txn;
    final color = view.isTransfer ? _slate : (view.category?.color ?? _slate);
    final (amount, amountColor) = switch (t.kind) {
      TxnKind.expense => (-t.amount, p.ink),
      TxnKind.income => (t.amount, p.positive),
      TxnKind.transfer => (t.amount, p.ink2),
    };
    var subtitle = view.subtitle;
    if (showDate) {
      subtitle = [subtitle, DateLabels.chip(t.date)].where((s) => s.isNotEmpty).join(' · ');
    }
    return Pressable(
      onTap: onTap ?? () => context.push('/txn/${t.id}'),
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.page, vertical: 9),
        child: Row(
          children: [
            EntityIcon(icon: view.iconKey, color: color, size: 44),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view.title,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const Gap(2),
                    Text(
                      subtitle,
                      style: context.text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Gap(Insets.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  amount,
                  sign: t.kind == TxnKind.income,
                  color: amountColor,
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (t.recurringId != null) ...[
                  const Gap(3),
                  Icon(Icons.autorenew_rounded, size: 13, color: p.ink3),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Swipe left to delete, with undo.
class SwipeToDelete extends ConsumerWidget {
  const SwipeToDelete({super.key, required this.txn, required this.child, this.aboveNavBar = true});

  final Txn txn;
  final Widget child;
  final bool aboveNavBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Dismissible(
      key: ValueKey('txn-${txn.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.32},
      background: ColoredBox(
        color: p.negativeFill,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: Insets.xxl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
                const Gap(6),
                Text('Delete', style: context.text.labelLarge?.copyWith(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
      onDismissed: (_) => deleteTxnWithUndo(context, ref, txn, aboveNavBar: aboveNavBar),
      child: child,
    );
  }
}

/// A day's transactions with the day's total.
class DayGroup {
  const DayGroup(this.day, this.items);

  final DateTime day;
  final List<TxnView> items;

  int get spent => items.where((v) => v.isExpense).fold(0, (s, v) => s + v.txn.amount);
  int get earned => items.where((v) => v.isIncome).fold(0, (s, v) => s + v.txn.amount);

  static List<DayGroup> group(Iterable<TxnView> views) {
    final map = groupBy(views, (TxnView v) => dateOnly(v.txn.date));
    final days = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final d in days) DayGroup(d, map[d]!)];
  }
}

class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.group});

  final DayGroup group;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final spent = group.spent;
    final earned = group.earned;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, Insets.xl, Insets.page, Insets.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateLabels.day(group.day),
              style: context.text.labelMedium?.copyWith(color: p.ink2, fontWeight: FontWeight.w700),
            ),
          ),
          if (spent > 0)
            MoneyText(-spent, style: context.text.labelMedium, color: p.ink3)
          else if (earned > 0)
            MoneyText(earned, sign: true, style: context.text.labelMedium, color: p.ink3),
        ],
      ),
    );
  }
}

/// Builds slivers for a day-grouped, swipeable transaction list.
List<Widget> txnDaySlivers(
  List<TxnView> views, {
  required Set<int> hidden,
  bool animate = true,
  bool swipe = true,
  bool aboveNavBar = true,
}) {
  final visible = views.where((v) => !hidden.contains(v.txn.id));
  final groups = DayGroup.group(visible);
  var index = 0;
  return [
    for (final g in groups)
      SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: DayHeader(group: g)),
          SliverList.list(
            children: [
              for (final v in g.items)
                _animated(
                  animate,
                  index++,
                  swipe
                      ? SwipeToDelete(
                          txn: v.txn,
                          aboveNavBar: aboveNavBar,
                          child: TxnTile(view: v),
                        )
                      : TxnTile(view: v),
                  ValueKey('row-${v.txn.id}'),
                ),
            ],
          ),
        ],
      ),
  ];
}

Widget _animated(bool animate, int index, Widget child, Key key) => animate && index < 14
    ? FadeSlideIn(key: key, index: index, child: child)
    : KeyedSubtree(key: key, child: child);
