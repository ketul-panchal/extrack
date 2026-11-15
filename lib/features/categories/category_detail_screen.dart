import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/domain/analytics.dart';
import 'package:spent/features/categories/categories_screen.dart';
import 'package:spent/features/insights/charts.dart';
import 'package:spent/features/plan/budget_editor_sheet.dart';
import 'package:spent/features/transactions/txn_actions.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/progress.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/txn_tile.dart';

class CategoryDetailScreen extends ConsumerWidget {
  const CategoryDetailScreen({super.key, required this.categoryId});

  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final category = ref.watch(categoryMapProvider)[categoryId];
    if (category == null) return Scaffold(appBar: AppBar());
    final calc = ref.watch(periodCalculatorProvider);
    final today = ref.watch(todayProvider);
    final money = ref.watch(moneyFormatProvider);
    final current = calc.month(today);
    final months = [for (var i = 5; i >= 0; i--) calc.shift(current, -i)];
    final txns = ref
        .watch(categoryTxnsProvider((categoryId, months.first.start, current.end)))
        .value;
    final hidden = ref.watch(pendingDeletionsProvider);
    final totals = [
      for (final m in months)
        (txns ?? const <Txn>[])
            .where((t) => m.contains(t.date) && t.kind != TxnKind.transfer)
            .fold<int>(0, (s, t) => s + t.amount),
    ];
    final thisMonth = totals.last;
    final pastWithData = totals.take(5).where((v) => v > 0).toList();
    final avg = pastWithData.isEmpty ? 0 : (pastWithData.sum / pastWithData.length).round();
    final budget = (ref.watch(budgetsProvider).value ?? const <Budget>[]).firstWhereOrNull(
      (b) => b.categoryId == categoryId,
    );
    final status = budget == null
        ? null
        : BudgetStatus(budget: budget, category: category, spent: thisMonth, period: current);
    final views = TxnView.build(
      (txns ?? const <Txn>[]).where((t) => current.contains(t.date)),
      ref.watch(categoryMapProvider),
      ref.watch(accountMapProvider),
    );
    final isExpense = category.kind == CategoryKind.expense;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'All transactions',
            onPressed: () => context.push('/search?category=$categoryId'),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'Options',
            onPressed: () => categoryActions(context, ref, category, popOnDelete: true),
          ),
          const Gap(Insets.sm),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
              child: Row(
                children: [
                  EntityIcon(icon: category.icon, color: category.color, size: 56),
                  const Gap(Insets.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name, style: context.text.headlineSmall),
                        Text(category.kind.label, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AppCard(
              margin: const EdgeInsets.symmetric(horizontal: Insets.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isExpense ? 'Spent this month' : 'Received this month',
                              style: context.text.labelMedium,
                            ),
                            const Gap(4),
                            MoneyText(
                              thisMonth,
                              style: context.text.headlineMedium,
                              tabular: false,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Monthly avg', style: context.text.labelMedium),
                          const Gap(4),
                          MoneyText(
                            avg,
                            style: context.text.titleMedium,
                            color: p.ink2,
                            tabular: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (status != null) ...[
                    const Gap(Insets.lg),
                    Builder(
                      builder: (context) {
                        final (fill, track) = levelColors(
                          context,
                          status.level,
                          okColor: p.entity(category.color),
                        );
                        return MeterBar(
                          value: status.fraction,
                          color: fill,
                          track: track,
                          marker: current.elapsedDays(today) / current.days,
                        );
                      },
                    ),
                    const Gap(Insets.sm),
                    Text(
                      status.remaining >= 0
                          ? '${money.format(status.remaining)} left of ${money.format(status.limit)}'
                          : '${money.format(-status.remaining)} over the ${money.format(status.limit)} budget',
                      style: context.text.bodySmall?.copyWith(
                        color: status.remaining < 0 ? p.negative : p.ink2,
                      ),
                    ),
                  ],
                  const Gap(Insets.lg),
                  Row(
                    children: [
                      if (isExpense) ...[
                        Expanded(
                          child: AppButton.secondary(
                            label: budget == null ? 'Set budget' : 'Budget',
                            icon: Icons.savings_outlined,
                            height: 46,
                            onPressed: () => showBudgetEditor(context, categoryId: categoryId),
                          ),
                        ),
                        const Gap(Insets.md),
                      ],
                      Expanded(
                        child: AppButton(
                          label: 'Add',
                          icon: Icons.add_rounded,
                          height: 46,
                          onPressed: () => context.push(
                            '/txn/new?kind=${isExpense ? 'expense' : 'income'}&category=$categoryId',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AppCard(
              margin: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last 6 months',
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Gap(Insets.lg),
                  TimeBarChart(
                    values: totals,
                    xLabels: [for (final m in months) DateFormat('MMM').format(m.lastDay)],
                    highlight: 5,
                    height: 170,
                    color: p.entity(category.color),
                    tooltipTitle: (i) => calc.label(months[i], now: today),
                    formatValue: money.format,
                    formatTick: (v) => money.compact(v.round(), symbol: false),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'This month',
              trailing: Text('${views.length}', style: context.text.labelMedium),
            ),
          ),
          if (views.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.page),
                child: Text(
                  'No transactions yet this month.',
                  style: context.text.bodyMedium?.copyWith(color: p.ink3),
                ),
              ),
            )
          else
            ...txnDaySlivers(views, hidden: hidden, aboveNavBar: false),
          SliverToBoxAdapter(child: Gap(MediaQuery.paddingOf(context).bottom + Insets.xxl)),
        ],
      ),
    );
  }
}
