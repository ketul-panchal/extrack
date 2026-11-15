import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/app/shell.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_icons.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/data/recurring_repository.dart';
import 'package:spent/domain/analytics.dart';
import 'package:spent/features/plan/budget_editor_sheet.dart';
import 'package:spent/features/plan/goal_sheets.dart';
import 'package:spent/features/plan/rule_detail_screen.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/period_switcher.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/progress.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/segmented.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';

enum PlanTab {
  budgets('Budgets'),
  goals('Goals'),
  bills('Bills');

  const PlanTab(this.label);
  final String label;
}

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  late PlanTab _tab = _parse(widget.initialTab) ?? PlanTab.budgets;
  Period? _period;

  static PlanTab? _parse(String? s) => PlanTab.values.where((t) => t.name == s).firstOrNull;

  @override
  void didUpdateWidget(PlanScreen old) {
    super.didUpdateWidget(old);
    final t = _parse(widget.initialTab);
    if (widget.initialTab != old.initialTab && t != null) _tab = t;
  }

  void _add() {
    switch (_tab) {
      case PlanTab.budgets:
        unawaited(showBudgetEditor(context, pickCategoryFirst: true));
      case PlanTab.goals:
        unawaited(showGoalEditor(context));
      case PlanTab.bills:
        unawaited(context.push('/recurring/new'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final calc = ref.watch(periodCalculatorProvider);
    final today = ref.watch(todayProvider);
    final period = _period ?? calc.month(today);
    final content = switch (_tab) {
      PlanTab.budgets => _BudgetsTab(period: period, onPeriod: (p) => setState(() => _period = p)),
      PlanTab.goals => const _GoalsTab(),
      PlanTab.bills => const _BillsTab(),
    };
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              title: 'Plan',
              actions: [
                CircleIconButton(
                  icon: Icons.add_rounded,
                  tooltip: switch (_tab) {
                    PlanTab.budgets => 'Add budget',
                    PlanTab.goals => 'New goal',
                    PlanTab.bills => 'New recurring',
                  },
                  onPressed: _add,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page),
              child: SegmentedTabs<PlanTab>(
                values: PlanTab.values,
                selected: _tab,
                labelOf: (t) => t.label,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.medium),
              switchInCurve: Motion.emphasized,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              child: KeyedSubtree(key: ValueKey(_tab), child: content),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: navBarClearance(context))),
        ],
      ),
    );
  }
}

// ── Budgets ────────────────────────────────────────────────────────────────

class _BudgetsTab extends ConsumerWidget {
  const _BudgetsTab({required this.period, required this.onPeriod});

  final Period period;
  final ValueChanged<Period> onPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calc = ref.watch(periodCalculatorProvider);
    final today = ref.watch(todayProvider);
    final statuses = ref.watch(budgetStatusesProvider(period)).value;
    final stats = ref.watch(periodStatsProvider(period)).value;
    final categories = ref.watch(categoryMapProvider);
    if (statuses == null) return const SizedBox(height: 200);
    final overall = statuses.where((s) => s.isOverall).firstOrNull;
    final byCategory = statuses.where((s) => !s.isOverall).toList();
    final budgeted = {for (final s in byCategory) s.budget.categoryId};
    final unbudgeted = (stats?.rankedExpense() ?? const <MapEntry<int?, int>>[])
        .where((e) => e.key != null && !budgeted.contains(e.key) && categories[e.key] != null)
        .toList();
    var i = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page - 4, Insets.lg, Insets.page - 4, 0),
          child: PeriodSwitcher(
            label: calc.label(period, now: today),
            sublabel: period.isCurrent(today)
                ? '${period.remainingDays(today)} days left'
                : 'Past cycle',
            canGoNext: !period.isCurrent(today),
            onPrevious: () => onPeriod(calc.previous(period)),
            onNext: () => onPeriod(calc.next(period)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
          child: FadeSlideIn(
            index: i++,
            child: overall == null
                ? AppCard(
                    onTap: () => showBudgetEditor(context),
                    child: Row(
                      children: [
                        Icon(Icons.savings_outlined, color: context.palette.accentText),
                        const Gap(Insets.md),
                        Expanded(
                          child: Text(
                            'Set an overall monthly budget',
                            style: context.text.titleSmall,
                          ),
                        ),
                        Icon(Icons.add_rounded, color: context.palette.ink2),
                      ],
                    ),
                  )
                : _OverallCard(status: overall, now: today),
          ),
        ),
        SectionHeader(
          title: 'By category',
          action: 'Add',
          onAction: () => showBudgetEditor(context, pickCategoryFirst: true),
        ),
        if (byCategory.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.page),
            child: Text(
              'Give your biggest categories their own limit to see where you stand at a glance.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.ink2),
            ),
          )
        else
          for (final s in byCategory)
            FadeSlideIn(
              index: i++,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.md),
                child: _CategoryBudgetCard(status: s, now: today),
              ),
            ),
        if (unbudgeted.isNotEmpty) ...[
          const SectionHeader(title: 'Not budgeted'),
          AppCard(
            margin: const EdgeInsets.symmetric(horizontal: Insets.page),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final e in unbudgeted.take(8))
                  Pressable(
                    onTap: () => context.push('/categories/${e.key}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 8),
                      child: Row(
                        children: [
                          EntityIcon(
                            icon: categories[e.key]!.icon,
                            color: categories[e.key]!.color,
                            size: 36,
                          ),
                          const Gap(Insets.md),
                          Expanded(
                            child: Text(categories[e.key]!.name, style: context.text.titleSmall),
                          ),
                          MoneyText(
                            e.value,
                            style: context.text.titleSmall,
                            color: context.palette.ink2,
                          ),
                          const Gap(Insets.sm),
                          Pressable(
                            onTap: () => showBudgetEditor(context, categoryId: e.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: context.palette.surface2,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                              child: Text(
                                'Limit',
                                style: context.text.labelMedium?.copyWith(
                                  color: context.palette.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.status, required this.now});

  final BudgetStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (fill, track) = levelColors(context, status.level);
    final current = status.period.isCurrent(now);
    final elapsed = status.period.elapsedDays(now) / status.period.days;
    final projected = status.projected(now);
    final over = status.remaining < 0;
    return AppCard(
      onTap: () => showBudgetEditor(context),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Monthly budget', style: context.text.labelMedium),
              const Spacer(),
              Icon(Icons.edit_outlined, size: 16, color: p.ink3),
            ],
          ),
          const Gap(6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              MoneyText(status.spent, style: context.text.headlineMedium, tabular: false),
              const Gap(6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'of '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: MoneyText(
                          status.limit,
                          style: context.text.titleSmall,
                          color: p.ink2,
                          tabular: false,
                        ),
                      ),
                    ],
                  ),
                  style: context.text.titleSmall?.copyWith(color: p.ink2),
                ),
              ),
            ],
          ),
          const Gap(Insets.md),
          MeterBar(
            value: status.fraction,
            color: fill,
            track: track,
            height: 10,
            marker: current ? elapsed : null,
          ),
          const Gap(Insets.md),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: over ? 'Over by' : 'Left',
                  child: MoneyText(
                    status.remaining.abs(),
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    color: over ? p.negative : p.ink,
                  ),
                ),
              ),
              if (current) ...[
                Expanded(
                  child: _MiniStat(
                    label: 'Safe per day',
                    child: MoneyText(
                      status.safePerDay(now),
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Projected',
                    child: MoneyText(
                      projected,
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      color: projected > status.limit ? p.warning : p.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (current) ...[
            const Gap(Insets.md),
            Row(
              children: [
                Container(width: 2, height: 12, color: p.ink.withValues(alpha: 0.55)),
                const Gap(6),
                Text(
                  'Where spending should be today',
                  style: context.text.labelSmall?.copyWith(letterSpacing: 0),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.text.labelSmall?.copyWith(letterSpacing: 0.1)),
      const Gap(2),
      child,
    ],
  );
}

class _CategoryBudgetCard extends StatelessWidget {
  const _CategoryBudgetCard({required this.status, required this.now});

  final BudgetStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = status.category!;
    final (fill, track) = levelColors(context, status.level, okColor: p.entity(c.color));
    final over = status.remaining < 0;
    final current = status.period.isCurrent(now);
    return AppCard(
      onTap: () => context.push('/categories/${c.id}'),
      onLongPress: () => showBudgetEditor(context, categoryId: c.id),
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              EntityIcon(icon: c.icon, color: c.color, size: 40),
              const Gap(Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: MoneyText(
                              status.spent,
                              style: context.text.bodySmall,
                              color: p.ink2,
                              tabular: false,
                            ),
                          ),
                          const TextSpan(text: ' of '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: MoneyText(
                              status.limit,
                              style: context.text.bodySmall,
                              color: p.ink2,
                              tabular: false,
                            ),
                          ),
                        ],
                      ),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    status.remaining.abs(),
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    color: over ? p.negative : p.ink,
                  ),
                  Text(
                    over ? 'over' : 'left',
                    style: context.text.labelSmall?.copyWith(
                      color: over ? p.negative : p.ink3,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Gap(Insets.md),
          MeterBar(
            value: status.fraction,
            color: fill,
            track: track,
            marker: current ? status.period.elapsedDays(now) / status.period.days : null,
          ),
        ],
      ),
    );
  }
}

// ── Goals ──────────────────────────────────────────────────────────────────

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider).value;
    if (goals == null) return const SizedBox(height: 200);
    final active = goals.where((g) => !g.goal.archived && g.goal.completedAt == null).toList();
    final done = goals.where((g) => !g.goal.archived && g.goal.completedAt != null).toList();
    if (active.isEmpty && done.isEmpty) {
      return EmptyState(
        icon: Icons.flag_rounded,
        title: 'Save for what matters',
        message: 'A trip, an emergency fund, a new phone — set a target and watch it fill up.',
        actionLabel: 'Create a goal',
        onAction: () => showGoalEditor(context),
      );
    }
    final total = active.fold<int>(0, (s, g) => s + g.saved);
    var i = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, Insets.xl, Insets.page, Insets.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Saved so far', style: context.text.labelMedium),
              const Spacer(),
              MoneyText(
                total,
                style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        for (final g in active)
          FadeSlideIn(
            index: i++,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, Insets.xs),
              child: GoalCard(progress: g),
            ),
          ),
        if (done.isNotEmpty) ...[
          const SectionHeader(title: 'Completed'),
          for (final g in done)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.md),
              child: GoalCard(progress: g),
            ),
        ],
      ],
    );
  }
}

class GoalCard extends ConsumerWidget {
  const GoalCard({super.key, required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final g = progress.goal;
    final color = p.entity(g.color);
    final money = ref.watch(moneyFormatProvider);
    final now = DateTime.now();
    String detail;
    if (progress.reached) {
      detail = 'Goal reached';
    } else if (g.deadline != null) {
      final months = monthsUntil(now, g.deadline!);
      detail = months <= 0
          ? 'Deadline passed · ${money.format(progress.remaining)} to go'
          : '${money.format((progress.remaining / months).ceil())}/month to hit ${DateLabels.monthYear(g.deadline!)}';
    } else {
      detail = '${money.format(progress.remaining)} to go';
    }
    if (ref.watch(hideAmountsProvider)) detail = progress.reached ? 'Goal reached' : 'In progress';
    return AppCard(
      onTap: () => context.push('/goals/${g.id}'),
      child: Row(
        children: [
          ProgressRing(
            value: progress.fraction,
            color: color,
            track: color.withValues(alpha: p.isDark ? 0.2 : 0.14),
            size: 60,
            stroke: 6,
            child: Icon(AppIcons.of(g.icon), color: color, size: 24),
          ),
          const Gap(Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.name,
                  style: context.text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(2),
                Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: MoneyText(
                          progress.saved,
                          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          tabular: false,
                        ),
                      ),
                      const TextSpan(text: '  of '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: MoneyText(
                          g.target,
                          style: context.text.bodySmall,
                          color: p.ink2,
                          tabular: false,
                        ),
                      ),
                    ],
                  ),
                  style: context.text.bodySmall,
                ),
                const Gap(4),
                Text(
                  detail,
                  style: context.text.labelSmall?.copyWith(
                    color: progress.reached ? p.positive : p.ink2,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Gap(Insets.sm),
          if (!progress.reached)
            CircleIconButton(
              icon: Icons.add_rounded,
              size: 38,
              iconSize: 20,
              tooltip: 'Add money',
              onPressed: () => showGoalMoneySheet(context, progress),
            )
          else
            Icon(Icons.verified_rounded, color: p.positive),
        ],
      ),
    );
  }
}

/// Whole months from [from] to [to], at least 1 if [to] is later this month.
int monthsUntil(DateTime from, DateTime to) {
  if (!to.isAfter(from)) return 0;
  final m = (to.year - from.year) * 12 + to.month - from.month;
  return m <= 0 ? 1 : m;
}

// ── Bills ──────────────────────────────────────────────────────────────────

class _BillsTab extends ConsumerWidget {
  const _BillsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringProvider).value;
    if (rules == null) return const SizedBox(height: 200);
    if (rules.isEmpty) {
      return EmptyState(
        icon: Icons.autorenew_rounded,
        title: 'No recurring payments',
        message:
            'Add rent, subscriptions and bills once. They\'re recorded automatically when due.',
        actionLabel: 'Add recurring',
        onAction: () => context.push('/recurring/new'),
      );
    }
    final active = rules.where((r) => r.active).toList();
    final paused = rules.where((r) => !r.active).toList();
    final monthlyOut = active
        .where((r) => r.kind == TxnKind.expense)
        .fold<double>(0, (s, r) => s + r.amount * r.frequency.perMonth(r.every))
        .round();
    final monthlyIn = active
        .where((r) => r.kind == TxnKind.income)
        .fold<double>(0, (s, r) => s + r.amount * r.frequency.perMonth(r.every))
        .round();
    final p = context.palette;
    var i = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, Insets.lg, Insets.page, 0),
          child: AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Monthly commitments', style: context.text.labelMedium),
                      const Gap(4),
                      MoneyText(monthlyOut, style: context.text.headlineSmall, tabular: false),
                    ],
                  ),
                ),
                if (monthlyIn > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Recurring income', style: context.text.labelMedium),
                      const Gap(4),
                      MoneyText(
                        monthlyIn,
                        sign: true,
                        color: p.positive,
                        style: context.text.titleMedium,
                        tabular: false,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SectionHeader(title: 'Upcoming'),
        for (final r in active)
          FadeSlideIn(
            index: i++,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.sm),
              child: RuleCard(rule: r),
            ),
          ),
        if (paused.isNotEmpty) ...[
          const SectionHeader(title: 'Paused & ended'),
          for (final r in paused)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.sm),
              child: Opacity(opacity: 0.6, child: RuleCard(rule: r)),
            ),
        ],
      ],
    );
  }
}

class RuleCard extends ConsumerWidget {
  const RuleCard({super.key, required this.rule});

  final RecurringRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final r = rule;
    final category = ref.watch(categoryMapProvider)[r.categoryId];
    final accounts = ref.watch(accountMapProvider);
    final today = ref.watch(todayProvider);
    final title = r.note.isNotEmpty
        ? r.note
        : r.kind == TxnKind.transfer
        ? 'Transfer to ${accounts[r.toAccountId]?.name ?? '—'}'
        : category?.name ?? 'Recurring';
    final overdue = r.active && r.nextDue.isBefore(today);
    final due = r.active
        ? (overdue ? 'Overdue · ${DateLabels.due(r.nextDue)}' : 'Next ${DateLabels.due(r.nextDue)}')
        : 'Paused';
    final isEmi = r.endDate != null;
    final emiTxns = isEmi
        ? (ref.watch(recurringTxnsProvider(r.id)).value ?? const <Txn>[])
        : const <Txn>[];
    final emiStats = isEmi ? RuleScheduleStats.compute(r, emiTxns, today) : null;
    final entityColorInt = category?.color ?? EntityColors.slate.light.toARGB32();
    final entityColor = p.entity(entityColorInt);
    final subtitleText = emiStats != null
        ? '${r.frequency.label(r.every)} · ${emiStats.paidCount}/${emiStats.totalCount} paid · ${emiStats.completed ? 'Completed' : due}'
        : '${r.frequency.label(r.every)} · $due';
    return AppCard(
      onTap: () => context.push('/recurring/${r.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              EntityIcon(
                icon: r.kind == TxnKind.transfer ? 'repeat' : (category?.icon ?? 'repeat'),
                color: entityColorInt,
                size: 42,
              ),
              const Gap(Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: context.text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isEmi) ...[
                          const Gap(6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: p.accentSoft,
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: Text(
                              'EMI',
                              style: context.text.labelSmall?.copyWith(
                                color: p.accentText,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Gap(2),
                    Text(
                      subtitleText,
                      style: context.text.bodySmall?.copyWith(color: overdue ? p.negative : p.ink2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Gap(Insets.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    r.kind == TxnKind.expense ? -r.amount : r.amount,
                    sign: r.kind == TxnKind.income,
                    color: r.kind == TxnKind.income ? p.positive : p.ink,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Gap(4),
                  if (r.active && !r.autoPost)
                    Pressable(
                      onTap: () => _payOrSkip(context, ref, r, title),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.primary,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          'Pay',
                          style: context.text.labelSmall?.copyWith(color: p.onPrimary),
                        ),
                      ),
                    )
                  else
                    Text(
                      r.autoPost ? 'Auto' : '',
                      style: context.text.labelSmall?.copyWith(letterSpacing: 0.2),
                    ),
                ],
              ),
            ],
          ),
          if (emiStats != null && emiStats.totalCount > 0) ...[
            const Gap(10),
            MeterBar(
              value: emiStats.fraction,
              color: emiStats.completed ? p.positive : entityColor,
              track: (emiStats.completed ? p.positive : entityColor).withValues(
                alpha: p.isDark ? 0.2 : 0.14,
              ),
              height: 5,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _payOrSkip(
    BuildContext context,
    WidgetRef ref,
    RecurringRule r,
    String title,
  ) async {
    final repo = ref.read(recurringRepositoryProvider);
    final next = RecurringRepository.recurrenceOf(r).after(r.nextDue);
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: title, subtitle: 'Due ${DateLabels.due(r.nextDue)}'),
          OptionRow(
            leading: const Icon(Icons.check_circle_outline_rounded),
            title: 'Mark as paid',
            subtitle: 'Records it today and moves to the next date',
            onTap: () => Navigator.pop(ctx, 'pay'),
          ),
          OptionRow(
            leading: const Icon(Icons.skip_next_outlined),
            title: 'Skip this time',
            subtitle: 'Next would be ${DateLabels.short(next)}',
            onTap: () => Navigator.pop(ctx, 'skip'),
          ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (action == null) return;
    if (action == 'pay') {
      await repo.markPaid(r);
      Haptics.success();
      if (context.mounted) {
        AppToast.show(
          context,
          '$title marked as paid',
          icon: Icons.check_circle_rounded,
          tone: ToastTone.success,
          aboveNavBar: true,
        );
      }
    } else {
      await repo.skip(r);
      if (context.mounted) {
        AppToast.show(context, 'Skipped', icon: Icons.skip_next_rounded, aboveNavBar: true);
      }
    }
  }
}
