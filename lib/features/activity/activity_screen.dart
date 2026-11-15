import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/app/shell.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/domain/analytics.dart';
import 'package:spent/features/transactions/txn_actions.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/period_switcher.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/txn_tile.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  Period? _period;
  bool _calendar = false;
  DateTime? _day;

  @override
  Widget build(BuildContext context) {
    final calc = ref.watch(periodCalculatorProvider);
    final today = ref.watch(todayProvider);
    final period = _period ?? calc.month(today);
    final views = ref.watch(txnViewsInPeriodProvider(period));
    final stats = ref.watch(periodStatsProvider(period)).value;
    final hidden = ref.watch(pendingDeletionsProvider);
    final list = views.value;
    final selectedDay = _day != null && period.contains(_day!)
        ? _day!
        : (period.contains(today) ? today : period.start);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              title: 'Activity',
              actions: [
                CircleIconButton(
                  icon: Icons.search_rounded,
                  tooltip: 'Search',
                  onPressed: () => context.push('/search'),
                ),
                CircleIconButton(
                  icon: _calendar ? Icons.view_agenda_outlined : Icons.calendar_month_outlined,
                  tooltip: _calendar ? 'List view' : 'Calendar view',
                  onPressed: () {
                    Haptics.selection();
                    setState(() => _calendar = !_calendar);
                  },
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page - 4),
              child: PeriodSwitcher(
                label: calc.label(period, now: today),
                sublabel: period.isCurrent(today) ? 'This month' : null,
                canGoNext: !period.isCurrent(today),
                onPrevious: () => setState(() => _period = calc.previous(period)),
                onNext: () => setState(() => _period = calc.next(period)),
                onTapLabel: period.isCurrent(today) ? null : () => setState(() => _period = null),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
              child: _Summary(stats: stats),
            ),
          ),
          if (_calendar) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
                child: FadeSlideIn(
                  child: _CalendarGrid(
                    period: period,
                    stats: stats,
                    selected: selectedDay,
                    today: today,
                    onSelect: (d) {
                      Haptics.selection();
                      setState(() => _day = d);
                    },
                  ),
                ),
              ),
            ),
            if (list != null)
              ...txnDaySlivers(
                list.where((v) => dateOnly(v.txn.date) == selectedDay).toList(),
                hidden: hidden,
              ),
            if (list != null &&
                !list.any((v) => dateOnly(v.txn.date) == selectedDay && !hidden.contains(v.txn.id)))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Insets.xxl),
                  child: Text(
                    'Nothing on ${DateLabels.day(selectedDay)}.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(color: context.palette.ink3),
                  ),
                ),
              ),
          ] else if (list != null && list.where((v) => !hidden.contains(v.txn.id)).isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'No transactions',
                message: period.isCurrent(today)
                    ? 'Nothing recorded this month yet. Tap + to add one.'
                    : 'Nothing was recorded in ${calc.label(period, now: today)}.',
              ),
            )
          else if (list != null)
            ...txnDaySlivers(list, hidden: hidden),
          SliverToBoxAdapter(child: SizedBox(height: navBarClearance(context))),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.stats});

  final PeriodStats? stats;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = stats;
    Widget cell(String label, int amount, {Color? color, bool sign = false}) => Expanded(
      child: Column(
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: p.ink3)),
          const Gap(4),
          MoneyText(
            amount,
            sign: sign,
            color: color ?? p.ink,
            tabular: false,
            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    Widget divider() => Container(width: 1, height: 32, color: p.hairline);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Row(
        children: [
          cell('Spent', s?.expense ?? 0),
          divider(),
          cell('Income', s?.income ?? 0, color: p.positive),
          divider(),
          cell('Net', s?.net ?? 0, sign: true, color: (s?.net ?? 0) < 0 ? p.negative : p.ink),
        ],
      ),
    );
  }
}

/// Month grid where each day is tinted by how much was spent (one hue,
/// light → dark), with the amount underneath.
class _CalendarGrid extends ConsumerWidget {
  const _CalendarGrid({
    required this.period,
    required this.stats,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final Period period;
  final PeriodStats? stats;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final calc = ref.watch(periodCalculatorProvider);
    final money = ref.watch(moneyFormatProvider);
    final hidden = ref.watch(hideAmountsProvider);
    final buckets = stats?.buckets ?? const <Bucket>[];
    final maxSpend = buckets.fold<int>(0, (m, b) => math.max(m, b.expense));
    final offset = (period.start.weekday - calc.weekStartDay + 7) % 7;
    final names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final weekdays = [for (var i = 0; i < 7; i++) names[(calc.weekStartDay - 1 + i) % 7]];
    final cells = offset + period.days;
    final rows = (cells / 7).ceil();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in weekdays)
                Expanded(
                  child: Center(child: Text(w, style: context.text.labelSmall)),
                ),
            ],
          ),
          const Gap(Insets.sm),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final index = r * 7 + c - offset;
                          if (index < 0 || index >= period.days) return const SizedBox(height: 50);
                          final day = DateTime(
                            period.start.year,
                            period.start.month,
                            period.start.day + index,
                          );
                          final spent = index < buckets.length ? buckets[index].expense : 0;
                          final t = maxSpend == 0 || spent == 0 ? 0.0 : math.sqrt(spent / maxSpend);
                          final isSelected = day == selected;
                          final isToday = day == today;
                          final future = day.isAfter(today);
                          final strong = t > 0.55;
                          final bg = isSelected
                              ? p.primary
                              : spent > 0
                              ? p.accent.withValues(alpha: 0.10 + 0.62 * t)
                              : Colors.transparent;
                          final fg = isSelected
                              ? p.onPrimary
                              : (strong ? p.onAccent : (future ? p.ink3 : p.ink));
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelect(day),
                            child: AnimatedContainer(
                              duration: Motion.medium,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 50,
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(12),
                                border: isToday && !isSelected
                                    ? Border.all(color: p.ink, width: 1.4)
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: context.text.labelLarge?.copyWith(
                                      color: fg,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (spent > 0)
                                    Text(
                                      hidden ? '•••' : money.compact(spent, symbol: false),
                                      maxLines: 1,
                                      style: context.text.labelSmall?.copyWith(
                                        color: fg.withValues(
                                          alpha: isSelected || strong ? 0.85 : 0.6,
                                        ),
                                        letterSpacing: 0,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          const Gap(6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Less', style: context.text.labelSmall),
              const Gap(6),
              for (final t in [0.15, 0.4, 0.65, 0.9])
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.10 + 0.62 * t),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Gap(3),
              Text('More spent', style: context.text.labelSmall),
              const Gap(6),
            ],
          ),
        ],
      ),
    );
  }
}
