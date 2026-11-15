import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/app/shell.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/domain/analytics.dart';
import 'package:spent/features/plan/budget_editor_sheet.dart';
import 'package:spent/features/transactions/txn_actions.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/progress.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';
import 'package:spent/shared/widgets/txn_tile.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Period? _customPeriod;

  Future<void> _pickPeriod(Period currentPeriod, DateTime today) async {
    final calc = ref.read(periodCalculatorProvider);
    final firstDate = await ref.read(txnRepositoryProvider).firstDate();
    if (!mounted) return;
    final minYear = math.min(today.year - 5, (firstDate?.year ?? today.year) - 1);
    final picked = await showAppSheet<Period>(
      context,
      builder: (ctx) => _DashboardPeriodSheet(
        selected: currentPeriod,
        today: today,
        calc: calc,
        minYear: minYear,
      ),
    );
    if (picked == null || !mounted) return;
    final defaultMonth = calc.month(today);
    setState(() {
      _customPeriod = picked == defaultMonth ? null : picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final calc = ref.watch(periodCalculatorProvider);
    final today = ref.watch(todayProvider);
    final defaultPeriod = ref.watch(currentMonthProvider);
    final period = _customPeriod ?? defaultPeriod;
    final isDefaultPeriod = period == defaultPeriod;

    final stats = ref.watch(periodStatsProvider(period)).value;
    final statuses = ref.watch(budgetStatusesProvider(period)).value ?? const <BudgetStatus>[];
    final overall = period.type == PeriodType.month
        ? statuses.where((s) => s.isOverall).firstOrNull
        : null;

    final recent = ref.watch(recentTxnViewsProvider).value;
    final periodViews = isDefaultPeriod
        ? null
        : ref.watch(txnViewsInPeriodProvider(period)).value;
    final bills = ref.watch(upcomingBillsProvider(7));
    final hidden = ref.watch(pendingDeletionsProvider);

    final activeSource = isDefaultPeriod ? recent : periodViews;
    final visibleRecent = activeSource
        ?.where((v) => !hidden.contains(v.txn.id))
        .take(6)
        .toList();

    var i = 0;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              period: period,
              isDefaultPeriod: isDefaultPeriod,
              onTapPeriod: () => _pickPeriod(period, today),
              onResetToday: isDefaultPeriod
                  ? null
                  : () {
                      Haptics.selection();
                      setState(() => _customPeriod = null);
                    },
            ),
          ),
          SliverToBoxAdapter(
            child: FadeSlideIn(
              index: i++,
              child: _BalanceCard(stats: stats),
            ),
          ),
          if (period.type == PeriodType.month)
            SliverToBoxAdapter(
              child: FadeSlideIn(
                index: i++,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
                  child: overall == null
                      ? const _BudgetPrompt()
                      : _BudgetCard(status: overall, now: today),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: FadeSlideIn(index: i++, child: const _AccountsStrip()),
          ),
          if (bills.isNotEmpty)
            SliverToBoxAdapter(
              child: FadeSlideIn(
                index: i++,
                child: _Upcoming(bills: bills.take(3).toList()),
              ),
            ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Recent',
              action: visibleRecent?.isNotEmpty == true ? 'See all' : null,
              onAction: () => context.go('/activity'),
            ),
          ),
          if (visibleRecent != null && visibleRecent.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'Nothing here yet',
                message: isDefaultPeriod
                    ? 'Tap + to add your first expense.\nEverything stays private, on this phone.'
                    : 'No transactions recorded in ${calc.label(period, now: today)}.',
                compact: true,
              ),
            )
          else if (visibleRecent != null)
            SliverToBoxAdapter(
              child: FadeSlideIn(
                index: i++,
                child: AppCard(
                  margin: const EdgeInsets.symmetric(horizontal: Insets.page),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final v in visibleRecent)
                        TxnTile(key: ValueKey(v.txn.id), view: v, showDate: true),
                    ],
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: navBarClearance(context))),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.period,
    required this.isDefaultPeriod,
    required this.onTapPeriod,
    this.onResetToday,
  });

  final Period period;
  final bool isDefaultPeriod;
  final VoidCallback onTapPeriod;
  final VoidCallback? onResetToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final name = ref.watch(settingsProvider.select((s) => s.name));
    final calc = ref.watch(periodCalculatorProvider);
    final today = ref.watch(todayProvider);
    final greeting = DateLabels.greeting(DateTime.now());
    final subtitle = name.trim().isEmpty ? greeting : '$greeting, ${name.trim()}';
    final titleText = period.type == PeriodType.year
        ? 'Year ${period.start.year}'
        : calc.label(period, now: today);

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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        subtitle,
                        style: context.text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onResetToday != null) ...[
                      const Gap(8),
                      Pressable(
                        onTap: onResetToday,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.accentSoft,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            'Current',
                            style: context.text.labelSmall?.copyWith(
                              color: p.accentText,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const Gap(2),
                Pressable(
                  onTap: () {
                    Haptics.selection();
                    onTapPeriod();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          titleText,
                          style: context.text.headlineLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Gap(4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 24,
                        color: p.ink2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          CircleIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Search',
            onPressed: () => context.push('/search'),
          ),
          const Gap(Insets.xs),
          CircleIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class _DashboardPeriodSheet extends StatefulWidget {
  const _DashboardPeriodSheet({
    required this.selected,
    required this.today,
    required this.calc,
    required this.minYear,
  });

  final Period selected;
  final DateTime today;
  final PeriodCalculator calc;
  final int minYear;

  @override
  State<_DashboardPeriodSheet> createState() => _DashboardPeriodSheetState();
}

class _DashboardPeriodSheetState extends State<_DashboardPeriodSheet> {
  late int _year = widget.selected.start.year;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final currentMonthPeriod = widget.calc.month(widget.today);
    final isFullYearSelected =
        widget.selected.type == PeriodType.year && widget.selected.start.year == _year;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, Insets.xs, Insets.page, Insets.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select period', style: context.text.headlineSmall),
                    const Gap(2),
                    Text(
                      'Choose any month or full year',
                      style: context.text.bodySmall?.copyWith(color: p.ink2),
                    ),
                  ],
                ),
              ),
              if (widget.selected != currentMonthPeriod)
                Pressable(
                  onTap: () {
                    Haptics.selection();
                    Navigator.pop(context, currentMonthPeriod);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.accentSoft,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      'This month',
                      style: context.text.labelMedium?.copyWith(color: p.accentText),
                    ),
                  ),
                ),
            ],
          ),
          const Gap(Insets.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              children: [
                CircleIconButton(
                  icon: Icons.chevron_left_rounded,
                  size: 36,
                  iconSize: 20,
                  tooltip: 'Previous year',
                  onPressed: _year > widget.minYear
                      ? () {
                          Haptics.selection();
                          setState(() => _year--);
                        }
                      : null,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$_year',
                      style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                CircleIconButton(
                  icon: Icons.chevron_right_rounded,
                  size: 36,
                  iconSize: 20,
                  tooltip: 'Next year',
                  onPressed: _year < widget.today.year
                      ? () {
                          Haptics.selection();
                          setState(() => _year++);
                        }
                      : null,
                ),
              ],
            ),
          ),
          const Gap(Insets.md),
          Pressable(
            onTap: () {
              Haptics.selection();
              Navigator.pop(context, widget.calc.year(DateTime(_year)));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 12),
              decoration: BoxDecoration(
                color: isFullYearSelected ? p.primary : p.surface2,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: isFullYearSelected ? p.primary : p.hairline,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: isFullYearSelected ? p.onPrimary : p.ink2,
                  ),
                  const Gap(8),
                  Text(
                    'Full Year $_year',
                    style: context.text.titleSmall?.copyWith(
                      color: isFullYearSelected ? p.onPrimary : p.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(Insets.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
            ),
            itemBuilder: (context, index) {
              final monthNum = index + 1;
              final monthDate = DateTime(_year, monthNum, widget.calc.monthStartDay.clamp(1, 28));
              final candidate = widget.calc.month(monthDate);
              final isFuture =
                  _year == widget.today.year && monthNum > widget.today.month;
              final isSelected =
                  widget.selected.type == PeriodType.month &&
                  widget.selected.start.year == _year &&
                  widget.selected.start.month == candidate.start.month;
              final isCurrentMonth = candidate == currentMonthPeriod;
              final label = DateFormat('MMM').format(DateTime(_year, monthNum));

              return Pressable(
                onTap: isFuture
                    ? null
                    : () {
                        Haptics.selection();
                        Navigator.pop(context, candidate);
                      },
                child: AnimatedContainer(
                  duration: Motion.fast,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? p.primary
                        : isCurrentMonth
                        ? p.accentSoft
                        : p.surface2,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: isCurrentMonth && !isSelected
                        ? Border.all(color: p.accent, width: 1.2)
                        : null,
                  ),
                  child: Text(
                    label,
                    style: context.text.titleSmall?.copyWith(
                      color: isSelected
                          ? p.onPrimary
                          : isFuture
                          ? p.ink3.withValues(alpha: 0.45)
                          : isCurrentMonth
                          ? p.accentText
                          : p.ink,
                      fontWeight: isSelected || isCurrentMonth ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.stats});

  final PeriodStats? stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final total = ref.watch(netWorthProvider);
    final hidden = ref.watch(hideAmountsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.page),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: ColoredBox(
          color: p.heroBg,
          child: Stack(
            children: [
              // Soft accent glow in the corner.
              Positioned(
                top: -90,
                right: -60,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.accent.withValues(alpha: p.isDark ? 0.35 : 0.55),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 14, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Total balance',
                          style: context.text.labelMedium?.copyWith(color: p.heroInk2),
                        ),
                        const Spacer(),
                        Pressable(
                          pressedScale: 0.85,
                          semanticLabel: hidden ? 'Show amounts' : 'Hide amounts',
                          onTap: () {
                            Haptics.light();
                            unawaited(
                              ref
                                  .read(settingsProvider.notifier)
                                  .update((s) => s.copyWith(hideAmounts: !hidden)),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: AnimatedSwitcher(
                              duration: Motion.fast,
                              child: Icon(
                                hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                key: ValueKey(hidden),
                                size: 20,
                                color: p.heroInk2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedMoney(
                        total,
                        style: context.text.displayMedium?.copyWith(color: p.heroInk, fontSize: 40),
                      ),
                    ),
                    const Gap(Insets.lg),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _HeroStat(
                              label: 'Income',
                              icon: Icons.south_west_rounded,
                              amount: stats?.income ?? 0,
                              tint: p.isDark ? p.positive : const Color(0xFF5BE3A5),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: _HeroStat(
                              label: 'Spent',
                              icon: Icons.north_east_rounded,
                              amount: stats?.expense ?? 0,
                              tint: p.isDark ? p.negative : const Color(0xFFFF8A8A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.icon,
    required this.amount,
    required this.tint,
  });

  final String label;
  final IconData icon;
  final int amount;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.heroInk.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: tint),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.text.labelSmall?.copyWith(color: p.heroInk2, letterSpacing: 0.2),
                ),
                const Gap(1),
                MoneyText(
                  amount,
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  color: p.heroInk,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.status, required this.now});

  final BudgetStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (fill, track) = levelColors(context, status.level);
    final isCurrent = status.period.isCurrent(now);
    final daysLeft = status.period.remainingDays(now);
    final pace = status.pace(now);
    final over = status.remaining < 0;
    final pct = (status.fraction * 100).round();
    return AppCard(
      onTap: () => context.go('/plan'),
      child: Row(
        children: [
          ProgressRing(
            value: status.fraction,
            color: fill,
            track: track,
            size: 78,
            stroke: 9,
            child: Text(
              '$pct%',
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const Gap(Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: MoneyText(
                        over ? -status.remaining : status.remaining,
                        style: context.text.titleLarge,
                        color: over ? p.negative : p.ink,
                        tabular: false,
                      ),
                    ),
                    const Gap(6),
                    Text(
                      over ? 'over' : 'left',
                      style: context.text.titleMedium?.copyWith(color: p.ink2),
                    ),
                  ],
                ),
                const Gap(2),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'of '),
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
                      TextSpan(
                        text: isCurrent
                            ? ' · ${daysLeft == 1 ? 'last day' : '$daysLeft days left'}'
                            : ' · Past cycle',
                      ),
                    ],
                  ),
                  style: context.text.bodySmall,
                ),
                const Gap(10),
                if (!over && isCurrent && daysLeft > 0)
                  _Pill(
                    icon: Icons.bolt_rounded,
                    color: p.accentText,
                    background: p.accentSoft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MoneyText(
                          status.safePerDay(now),
                          style: context.text.labelMedium,
                          color: p.accentText,
                          tabular: false,
                        ),
                        Text(
                          ' / day is safe',
                          style: context.text.labelMedium?.copyWith(color: p.accentText),
                        ),
                      ],
                    ),
                  )
                else if (over)
                  _Pill(
                    icon: Icons.error_outline_rounded,
                    color: p.negative,
                    background: p.negativeFill.withValues(alpha: 0.12),
                    child: Text(
                      'Over budget',
                      style: context.text.labelMedium?.copyWith(color: p.negative),
                    ),
                  )
                else
                  _Pill(
                    icon: Icons.check_circle_outline_rounded,
                    color: p.positive,
                    background: p.positiveFill.withValues(alpha: 0.12),
                    child: Text(
                      'Within budget',
                      style: context.text.labelMedium?.copyWith(color: p.positive),
                    ),
                  ),
                if (!over && isCurrent && pace > 1.1 && status.period.elapsedDays(now) > 3) ...[
                  const Gap(6),
                  Text(
                    'Spending faster than planned',
                    style: context.text.labelSmall?.copyWith(color: p.warning, letterSpacing: 0),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.color,
    required this.background,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.pill)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const Gap(4),
        Flexible(child: child),
      ],
    ),
  );
}

class _BudgetPrompt extends StatelessWidget {
  const _BudgetPrompt();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      onTap: () => showBudgetEditor(context),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: ShapeDecoration(
              color: p.accentSoft,
              shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Icon(Icons.savings_outlined, color: p.accentText),
          ),
          const Gap(Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Set a monthly budget', style: context.text.titleSmall),
                const Gap(2),
                Text('See what you can safely spend each day.', style: context.text.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.ink3),
        ],
      ),
    );
  }
}

class _AccountsStrip extends ConsumerWidget {
  const _AccountsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider);
    final balances = ref.watch(balancesProvider).value ?? const <int, int>{};
    final p = context.palette;
    return Column(
      children: [
        SectionHeader(
          title: 'Accounts',
          action: 'Manage',
          onAction: () => context.push('/accounts'),
        ),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Insets.page),
            clipBehavior: Clip.none,
            itemCount: accounts.length + 1,
            separatorBuilder: (_, _) => const Gap(Insets.md),
            itemBuilder: (context, i) {
              if (i == accounts.length) {
                return Pressable(
                  onTap: () => context.push('/accounts?new=1'),
                  child: Container(
                    width: 108,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(color: p.hairline, width: 1.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded, color: p.ink2),
                        const Gap(4),
                        Text('Add', style: context.text.labelMedium),
                      ],
                    ),
                  ),
                );
              }
              final a = accounts[i];
              final balance = balances[a.id] ?? a.openingBalance;
              return SizedBox(
                width: 160,
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => context.push('/accounts/${a.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EntityIcon(icon: a.icon, color: a.color, size: 34),
                      const Spacer(),
                      Text(
                        a.name,
                        style: context.text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Gap(2),
                      MoneyText(
                        balance,
                        style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        color: balance < 0 ? p.negative : p.ink,
                        tabular: false,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming({required this.bills});

  final List<UpcomingBill> bills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final categories = ref.watch(categoryMapProvider);
    final today = ref.watch(todayProvider);
    return Column(
      children: [
        SectionHeader(
          title: 'Upcoming',
          action: 'Bills',
          onAction: () => context.go('/plan?tab=bills'),
        ),
        AppCard(
          margin: const EdgeInsets.symmetric(horizontal: Insets.page),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final b in bills)
                Builder(
                  builder: (context) {
                    final r = b.rule;
                    final c = categories[r.categoryId];
                    final overdue = r.nextDue.isBefore(today);
                    final title = r.note.isNotEmpty ? r.note : (c?.name ?? 'Transfer');
                    return Pressable(
                      onTap: () => context.push('/recurring/${r.id}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 9),
                        child: Row(
                          children: [
                            EntityIcon(
                              icon: c?.icon ?? 'repeat',
                              color: c?.color ?? EntityColors.slate.light.toARGB32(),
                              size: 40,
                            ),
                            const Gap(Insets.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: context.text.titleSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    overdue
                                        ? 'Overdue · due ${DateLabels.due(r.nextDue)}'
                                        : 'Due ${DateLabels.due(r.nextDue)}',
                                    style: context.text.bodySmall?.copyWith(
                                      color: overdue ? p.negative : p.ink2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Gap(Insets.sm),
                            MoneyText(
                              r.amount,
                              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Gap(Insets.sm),
                            if (r.autoPost)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: p.surface2,
                                  borderRadius: BorderRadius.circular(Radii.pill),
                                ),
                                child: Text(
                                  'Auto',
                                  style: context.text.labelSmall?.copyWith(color: p.ink2),
                                ),
                              )
                            else
                              Pressable(
                                onTap: () async {
                                  await ref.read(recurringRepositoryProvider).markPaid(r);
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
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: p.primary,
                                    borderRadius: BorderRadius.circular(Radii.pill),
                                  ),
                                  child: Text(
                                    'Pay',
                                    style: context.text.labelMedium?.copyWith(color: p.onPrimary),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
