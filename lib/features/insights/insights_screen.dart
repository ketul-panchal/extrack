import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/app/shell.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/domain/analytics.dart';
import 'package:spent/features/insights/charts.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/period_switcher.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/progress.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/segmented.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  PeriodType _type = PeriodType.month;
  Period? _period;
  bool _income = false;
  int? _slice;

  @override
  Widget build(BuildContext context) {
    final calc = ref.watch(periodCalculatorProvider);
    final today = ref.watch(todayProvider);
    final period = _period ?? calc.of(_type, today);
    final previous = calc.previous(period);
    final cur = ref.watch(periodStatsProvider(period)).value;
    final prev = ref.watch(periodStatsProvider(previous)).value;
    final ongoing = period.isCurrent(today);
    final money = ref.watch(moneyFormatProvider);

    final slivers = <Widget>[];
    if (cur != null && prev != null) {
      if (cur.isEmpty && prev.isEmpty) {
        slivers.add(
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.insights_rounded,
              title: 'No data for this period',
              message:
                  'Add a few transactions and your trends, breakdowns and tips will show up here.',
            ),
          ),
        );
      } else {
        final nowIndex = _indexOf(period, today);
        var i = 0;
        Widget item(Widget w) => FadeSlideIn(index: i++, child: w);
        slivers.add(
          SliverList.list(
            children: [
              item(_Kpis(cur: cur, prev: prev, ongoing: ongoing, nowIndex: nowIndex)),
              item(
                _ChartCard(
                  title: 'Spending',
                  subtitle: '${money.format(cur.averagePerDay(today))} a day on average',
                  child: TimeBarChart(
                    values: [for (final b in cur.buckets) b.expense],
                    xLabels: _xLabels(period, cur),
                    lastIndex: ongoing ? nowIndex : null,
                    highlight: ongoing ? nowIndex : null,
                    tooltipTitle: (i) => _title(period, cur.buckets[i].start),
                    formatValue: money.format,
                    formatTick: (v) => money.compact(v.round(), symbol: false),
                  ),
                ),
              ),
              if (prev.expense > 0 || cur.expense > 0)
                item(
                  _ChartCard(
                    title: 'Pace',
                    subtitle: _paceText(cur, prev, ongoing, nowIndex, money),
                    child: PaceChart(
                      current: cur.cumulativeExpense,
                      previous: prev.cumulativeExpense,
                      currentUntil: ongoing ? nowIndex : cur.buckets.length - 1,
                      xLabels: _xLabels(period, cur),
                      tooltipTitle: (i) => _type == PeriodType.year
                          ? DateFormat('MMMM').format(DateTime(2000, i + 1))
                          : 'Day ${i + 1}',
                      formatValue: money.format,
                      formatTick: (v) => money.compact(v.round(), symbol: false),
                      currentName: ongoing ? 'This ${_type.name}' : calc.label(period, now: today),
                      previousName: ongoing
                          ? 'Last ${_type.name}'
                          : calc.label(previous, now: today),
                    ),
                  ),
                ),
              item(
                _Breakdown(
                  cur: cur,
                  prev: prev,
                  income: _income,
                  selected: _slice,
                  onIncome: (v) => setState(() {
                    _income = v;
                    _slice = null;
                  }),
                  onSelect: (s) => setState(() => _slice = s),
                ),
              ),
              item(_StatsGrid(stats: cur, period: period, today: today)),
              ..._insightCards(cur, prev, today, money).map(item),
            ],
          ),
        );
      }
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: PageHeader(title: 'Insights')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page),
              child: SegmentedTabs<PeriodType>(
                values: PeriodType.values,
                selected: _type,
                labelOf: (t) => t.label,
                onChanged: (t) => setState(() {
                  _type = t;
                  _period = null;
                  _slice = null;
                }),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.page - 4,
                Insets.md,
                Insets.page - 4,
                Insets.sm,
              ),
              child: PeriodSwitcher(
                label: calc.label(period, now: today),
                sublabel: ongoing ? 'So far' : null,
                canGoNext: !ongoing,
                onPrevious: () => setState(() {
                  _period = previous;
                  _slice = null;
                }),
                onNext: () => setState(() {
                  _period = calc.next(period);
                  _slice = null;
                }),
                onTapLabel: ongoing ? null : () => setState(() => _period = null),
              ),
            ),
          ),
          ...slivers,
          SliverToBoxAdapter(child: SizedBox(height: navBarClearance(context))),
        ],
      ),
    );
  }

  int _indexOf(Period p, DateTime d) {
    if (p.type == PeriodType.year) return (d.year - p.start.year) * 12 + d.month - p.start.month;
    return math.min(daysBetween(p.start, d), p.days - 1);
  }

  List<String> _xLabels(Period p, PeriodStats s) => switch (p.type) {
    PeriodType.week => [for (final b in s.buckets) DateFormat('EEEEE').format(b.start)],
    PeriodType.month => [
      for (var i = 0; i < s.buckets.length; i++) i % 7 == 0 ? '${s.buckets[i].start.day}' : '',
    ],
    PeriodType.year => [for (final b in s.buckets) DateFormat('MMMMM').format(b.start)],
  };

  String _title(Period p, DateTime d) => p.type == PeriodType.year
      ? DateFormat('MMMM yyyy').format(d)
      : DateFormat('EEE, d MMM').format(d);

  String _paceText(
    PeriodStats cur,
    PeriodStats prev,
    bool ongoing,
    int nowIndex,
    MoneyFormat money,
  ) {
    if (ref.read(hideAmountsProvider)) return 'Compared with the previous ${_type.name}';
    final compare = ongoing
        ? (nowIndex < prev.cumulativeExpense.length
              ? prev.cumulativeExpense[nowIndex]
              : prev.expense)
        : prev.expense;
    final diff = cur.expense - compare;
    final when = ongoing
        ? ' than at this point last ${_type.name}'
        : ' than the ${_type.name} before';
    if (diff.abs() < money.unit) return 'Same as last ${_type.name}';
    return diff < 0 ? '${money.format(-diff)} less$when' : '${money.format(diff)} more$when';
  }

  List<Widget> _insightCards(PeriodStats cur, PeriodStats prev, DateTime today, MoneyFormat money) {
    final insights = buildInsights(
      current: cur,
      previous: prev,
      categories: ref.read(categoryMapProvider),
      money: money,
      now: today,
    );
    if (insights.isEmpty || ref.read(hideAmountsProvider)) return const [];
    return [
      const SectionHeader(title: 'Highlights'),
      for (final insight in insights.take(5))
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.sm),
          child: _InsightCard(insight: insight),
        ),
    ];
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({
    required this.cur,
    required this.prev,
    required this.ongoing,
    required this.nowIndex,
  });

  final PeriodStats cur;
  final PeriodStats prev;
  final bool ongoing;
  final int nowIndex;

  int _prevAt(bool income) {
    if (!ongoing) return income ? prev.income : prev.expense;
    var sum = 0;
    for (var i = 0; i <= nowIndex && i < prev.buckets.length; i++) {
      sum += income ? prev.buckets[i].income : prev.buckets[i].expense;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final prevSpent = _prevAt(false);
    final prevIncome = _prevAt(true);
    final rate = cur.savingsRate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, 0),
      child: Row(
        children: [
          Expanded(
            child: _Kpi(label: 'Spent', value: cur.expense, previous: prevSpent, upIsGood: false),
          ),
          const Gap(Insets.sm),
          Expanded(
            child: _Kpi(label: 'Income', value: cur.income, previous: prevIncome, upIsGood: true),
          ),
          const Gap(Insets.sm),
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saved', style: context.text.labelMedium),
                  const Gap(4),
                  MoneyText(
                    cur.net,
                    compact: true,
                    tabular: false,
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    color: cur.net < 0 ? p.negative : p.ink,
                  ),
                  const Gap(6),
                  Text(
                    rate == null ? 'No income' : '${(rate * 100).round()}% of income',
                    style: context.text.labelSmall?.copyWith(letterSpacing: 0, color: p.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.previous,
    required this.upIsGood,
  });

  final String label;
  final int value;
  final int previous;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget delta;
    if (previous <= 0) {
      delta = Text('—', style: context.text.labelSmall);
    } else {
      final change = (value - previous) / previous;
      final pct = (change.abs() * 100).round();
      final up = change > 0;
      final good = up == upIsGood;
      final color = pct == 0 ? p.ink3 : (good ? p.positive : p.negative);
      delta = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pct == 0
                ? Icons.remove_rounded
                : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
            size: 13,
            color: color,
          ),
          const Gap(2),
          Flexible(
            child: Text(
              '$pct%',
              style: context.text.labelSmall?.copyWith(
                color: color,
                letterSpacing: 0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelMedium),
          const Gap(4),
          MoneyText(
            value,
            compact: true,
            tabular: false,
            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Gap(6),
          delta,
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    margin: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const Gap(2),
        Text(subtitle, style: context.text.bodySmall),
        const Gap(Insets.lg),
        child,
      ],
    ),
  );
}

class _Breakdown extends ConsumerWidget {
  const _Breakdown({
    required this.cur,
    required this.prev,
    required this.income,
    required this.selected,
    required this.onIncome,
    required this.onSelect,
  });

  final PeriodStats cur;
  final PeriodStats prev;
  final bool income;
  final int? selected;
  final ValueChanged<bool> onIncome;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final categories = ref.watch(categoryMapProvider);
    final ranked = income ? cur.rankedIncome() : cur.rankedExpense();
    final previous = income ? prev.incomeByCategory : prev.expenseByCategory;
    final total = income ? cur.income : cur.expense;
    final slate = EntityColors.slate.light.toARGB32();

    // Top five keep their own color; the tail folds into a neutral "Other".
    final top = ranked.take(ranked.length > 6 ? 5 : 6).toList();
    final rest = ranked.skip(top.length).fold<int>(0, (s, e) => s + e.value);
    final slices = [
      for (final e in top) DonutSlice(e.value, p.entity(categories[e.key]?.color ?? slate)),
      if (rest > 0) DonutSlice(rest, p.ink3.withValues(alpha: 0.5)),
    ];
    String nameOf(int index) {
      if (index >= top.length) return 'Other';
      return categories[top[index].key]?.name ?? 'Uncategorized';
    }

    final sel = selected != null && selected! < slices.length ? selected : null;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Where it ${income ? 'came from' : 'went'}',
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(
                width: 170,
                child: SegmentedTabs<bool>(
                  values: const [false, true],
                  selected: income,
                  height: 36,
                  labelOf: (v) => v ? 'Income' : 'Spending',
                  onChanged: onIncome,
                ),
              ),
            ],
          ),
          const Gap(Insets.lg),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
              child: Center(
                child: Text(
                  income ? 'No income in this period.' : 'No spending in this period.',
                  style: context.text.bodyMedium?.copyWith(color: p.ink3),
                ),
              ),
            )
          else ...[
            Center(
              child: DonutChart(
                slices: slices,
                selected: sel,
                onSelect: onSelect,
                size: 200,
                center: AnimatedSwitcher(
                  duration: Motion.fast,
                  child: Column(
                    key: ValueKey(sel),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          sel == null ? 'Total' : nameOf(sel),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium,
                        ),
                      ),
                      const Gap(2),
                      MoneyText(
                        sel == null ? total : slices[sel].value,
                        compact: true,
                        tabular: false,
                        style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (sel != null)
                        Text(
                          '${(slices[sel].value / total * 100).round()}%',
                          style: context.text.labelMedium?.copyWith(color: p.ink2),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(Insets.lg),
            for (var i = 0; i < ranked.length; i++)
              _BreakdownRow(
                categoryId: ranked[i].key,
                amount: ranked[i].value,
                share: ranked[i].value / total,
                previous: previous[ranked[i].key] ?? 0,
                upIsGood: income,
                highlighted: sel != null && (sel == i || (sel == top.length && i >= top.length)),
              ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends ConsumerWidget {
  const _BreakdownRow({
    required this.categoryId,
    required this.amount,
    required this.share,
    required this.previous,
    required this.upIsGood,
    required this.highlighted,
  });

  final int? categoryId;
  final int amount;
  final double share;
  final int previous;
  final bool upIsGood;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final c = ref.watch(categoryMapProvider)[categoryId];
    final slate = EntityColors.slate.light.toARGB32();
    final color = p.entity(c?.color ?? slate);
    String? delta;
    Color deltaColor = p.ink3;
    if (previous > 0) {
      final change = (amount - previous) / previous;
      final pct = (change.abs() * 100).round();
      if (pct >= 1) {
        delta = '${change > 0 ? '↑' : '↓'} $pct%';
        deltaColor = (change > 0) == upIsGood ? p.positive : p.negative;
      }
    } else {
      delta = 'new';
    }
    return Pressable(
      onTap: c == null ? null : () => context.push('/categories/${c.id}'),
      child: AnimatedContainer(
        duration: Motion.medium,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: highlighted ? p.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            EntityIcon(icon: c?.icon ?? 'other', color: c?.color ?? slate, size: 36),
            const Gap(Insets.md),
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c?.name ?? 'Uncategorized',
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      MoneyText(
                        amount,
                        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const Gap(6),
                  Row(
                    children: [
                      Expanded(
                        child: MeterBar(value: share, color: color, track: p.surface2, height: 5),
                      ),
                      const Gap(Insets.sm),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${(share * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: context.text.labelSmall?.copyWith(color: p.ink2, letterSpacing: 0),
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text(
                          delta ?? '',
                          textAlign: TextAlign.right,
                          style: context.text.labelSmall?.copyWith(
                            color: deltaColor,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid({required this.stats, required this.period, required this.today});

  final PeriodStats stats;
  final Period period;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final categories = ref.watch(categoryMapProvider);
    final largest = stats.largestExpense;
    final largestName = largest == null
        ? '—'
        : (largest.note.isNotEmpty
              ? largest.note
              : categories[largest.categoryId]?.name ?? 'Expense');
    final peak = stats.peakBucket;
    Widget tile(IconData icon, String label, Widget value, String? foot) => Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: p.ink2),
            const Gap(Insets.md),
            Text(label, style: context.text.labelMedium),
            const Gap(2),
            value,
            if (foot != null) ...[
              const Gap(2),
              Text(
                foot,
                style: context.text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
    final big = context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800);
    final isYear = period.type == PeriodType.year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
      child: Column(
        children: [
          Row(
            children: [
              tile(
                Icons.calendar_view_day_rounded,
                'Daily average',
                MoneyText(stats.averagePerDay(today), style: big, tabular: false),
                null,
              ),
              const Gap(Insets.sm),
              tile(
                Icons.north_east_rounded,
                'Biggest expense',
                MoneyText(largest?.amount ?? 0, style: big, tabular: false),
                largest == null
                    ? null
                    : '$largestName · ${DateFormat('d MMM').format(largest.date)}',
              ),
            ],
          ),
          const Gap(Insets.sm),
          Row(
            children: [
              tile(
                Icons.receipt_long_outlined,
                'Transactions',
                Text('${stats.count}', style: big),
                null,
              ),
              const Gap(Insets.sm),
              if (isYear)
                tile(
                  Icons.local_fire_department_outlined,
                  'Top month',
                  MoneyText(peak?.expense ?? 0, style: big, tabular: false),
                  peak == null || peak.expense == 0 ? null : DateFormat('MMMM').format(peak.start),
                )
              else
                tile(
                  Icons.spa_outlined,
                  'No-spend days',
                  Text('${stats.noSpendDays(today)}', style: big),
                  peak == null || peak.expense == 0
                      ? null
                      : 'Peak: ${DateLabels.short(peak.start)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (fg, bg) = switch (insight.tone) {
      InsightTone.good => (p.positive, p.positiveFill.withValues(alpha: 0.13)),
      InsightTone.bad => (p.negative, p.negativeFill.withValues(alpha: 0.12)),
      InsightTone.neutral => (p.ink2, p.surface2),
    };
    final icon = switch (insight.icon) {
      InsightIcon.trendDown => Icons.trending_down_rounded,
      InsightIcon.trendUp => Icons.trending_up_rounded,
      InsightIcon.calendar => Icons.calendar_month_rounded,
      InsightIcon.star => Icons.star_rounded,
      InsightIcon.piggy => Icons.savings_rounded,
      InsightIcon.warning => Icons.warning_amber_rounded,
      InsightIcon.sparkle => Icons.auto_awesome_rounded,
    };
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: fg),
          ),
          const Gap(Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insight.title, style: context.text.titleSmall),
                const Gap(2),
                Text(insight.body, style: context.text.bodySmall?.copyWith(color: p.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
