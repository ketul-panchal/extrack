import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
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

/// A single installment in an EMI / fixed-term recurring schedule.
class EmiInstallment {
  const EmiInstallment({
    required this.number,
    required this.date,
    required this.amount,
    required this.isPaid,
    this.isNext = false,
    this.txn,
  });

  final int number;
  final DateTime date;
  final int amount;
  final bool isPaid;
  final bool isNext;
  final Txn? txn;
}

/// Computed payment & EMI statistics for a [RecurringRule].
class RuleScheduleStats {
  const RuleScheduleStats({
    required this.rule,
    required this.isEmi,
    required this.paidCount,
    required this.remainingCount,
    required this.totalCount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.totalAmount,
    required this.paidThisYear,
    required this.paidThisYearCount,
    required this.monthlyEquivalent,
    required this.yearlyEquivalent,
    required this.upcomingDates,
    required this.installments,
    required this.lastInstallmentDate,
  });

  factory RuleScheduleStats.compute(RecurringRule r, List<Txn> txns, DateTime today) {
    final rec = RecurringRepository.recurrenceOf(r);
    final isEmi = r.endDate != null;

    if (isEmi) {
      final end = dateOnly(r.endDate!);
      final nextDue = dateOnly(r.nextDue);
      final allFromStart = rec.occurrences(r.startDate, end, limit: 600);
      final upcoming = r.active && !nextDue.isAfter(end)
          ? rec.occurrences(nextDue, end, limit: 600)
          : const <DateTime>[];
      final pastScheduled = r.active
          ? allFromStart.where((d) => d.isBefore(nextDue)).toList()
          : allFromStart;

      // Sort recorded transactions oldest-first to pair with installments.
      final chronologicalTxns = txns.toList()
        ..sort((a, b) {
          final cmp = a.date.compareTo(b.date);
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });

      final paidInstallments = <EmiInstallment>[];
      if (chronologicalTxns.length >= pastScheduled.length) {
        for (var i = 0; i < chronologicalTxns.length; i++) {
          final t = chronologicalTxns[i];
          paidInstallments.add(
            EmiInstallment(
              number: i + 1,
              date: dateOnly(t.date),
              amount: t.amount,
              isPaid: true,
              txn: t,
            ),
          );
        }
      } else {
        // More past scheduled dates than recorded txns (e.g., rule was created mid-EMI).
        final unrecordedCount = pastScheduled.length - chronologicalTxns.length;
        for (var i = 0; i < unrecordedCount; i++) {
          paidInstallments.add(
            EmiInstallment(
              number: i + 1,
              date: pastScheduled[i],
              amount: r.amount,
              isPaid: true,
            ),
          );
        }
        for (var i = 0; i < chronologicalTxns.length; i++) {
          final t = chronologicalTxns[i];
          paidInstallments.add(
            EmiInstallment(
              number: unrecordedCount + i + 1,
              date: dateOnly(t.date),
              amount: t.amount,
              isPaid: true,
              txn: t,
            ),
          );
        }
      }

      final installments = <EmiInstallment>[
        ...paidInstallments,
        for (var i = 0; i < upcoming.length; i++)
          EmiInstallment(
            number: paidInstallments.length + i + 1,
            date: upcoming[i],
            amount: r.amount,
            isPaid: false,
            isNext: i == 0,
          ),
      ];

      final paidCount = paidInstallments.length;
      final remainingCount = upcoming.length;
      final totalCount = paidCount + remainingCount;
      final paidAmount = paidInstallments.fold<int>(0, (s, e) => s + e.amount);
      final remainingAmount = remainingCount * r.amount;
      final totalAmount = paidAmount + remainingAmount;
      final lastDate =
          upcoming.lastOrNull ??
          pastScheduled.lastOrNull ??
          paidInstallments.lastOrNull?.date ??
          end;

      final thisYearTxns = txns.where((t) => t.date.year == today.year);
      final monthlyEq = (r.amount * r.frequency.perMonth(r.every)).round();

      return RuleScheduleStats(
        rule: r,
        isEmi: true,
        paidCount: paidCount,
        remainingCount: remainingCount,
        totalCount: totalCount,
        paidAmount: paidAmount,
        remainingAmount: remainingAmount,
        totalAmount: totalAmount,
        paidThisYear: thisYearTxns.fold<int>(0, (s, t) => s + t.amount),
        paidThisYearCount: thisYearTxns.length,
        monthlyEquivalent: monthlyEq,
        yearlyEquivalent: monthlyEq * 12,
        upcomingDates: upcoming,
        installments: installments,
        lastInstallmentDate: lastDate,
      );
    }

    // Ongoing recurring rule (no endDate).
    final upcoming = r.active
        ? rec.occurrences(r.nextDue, DateTime(r.nextDue.year + 5), limit: 4)
        : const <DateTime>[];
    final paidAmount = txns.fold<int>(0, (s, t) => s + t.amount);
    final thisYearTxns = txns.where((t) => t.date.year == today.year).toList();
    final paidThisYear = thisYearTxns.fold<int>(0, (s, t) => s + t.amount);
    final monthlyEq = (r.amount * r.frequency.perMonth(r.every)).round();

    return RuleScheduleStats(
      rule: r,
      isEmi: false,
      paidCount: txns.length,
      remainingCount: 0,
      totalCount: txns.length,
      paidAmount: paidAmount,
      remainingAmount: 0,
      totalAmount: paidAmount,
      paidThisYear: paidThisYear,
      paidThisYearCount: thisYearTxns.length,
      monthlyEquivalent: monthlyEq,
      yearlyEquivalent: monthlyEq * 12,
      upcomingDates: upcoming,
      installments: const [],
      lastInstallmentDate: null,
    );
  }

  final RecurringRule rule;
  final bool isEmi;
  final int paidCount;
  final int remainingCount;
  final int totalCount;
  final int paidAmount;
  final int remainingAmount;
  final int totalAmount;
  final int paidThisYear;
  final int paidThisYearCount;
  final int monthlyEquivalent;
  final int yearlyEquivalent;
  final List<DateTime> upcomingDates;
  final List<EmiInstallment> installments;
  final DateTime? lastInstallmentDate;

  double get fraction => totalCount <= 0 ? 0 : (paidCount / totalCount).clamp(0.0, 1.0);
  bool get completed => isEmi && remainingCount == 0 && totalCount > 0;
}

class RuleDetailScreen extends ConsumerStatefulWidget {
  const RuleDetailScreen({super.key, required this.ruleId});

  final int ruleId;

  @override
  ConsumerState<RuleDetailScreen> createState() => _RuleDetailScreenState();
}

class _RuleDetailScreenState extends ConsumerState<RuleDetailScreen> {
  bool _showAllInstallments = false;

  String _titleOf(RecurringRule r, Category? category, Map<int, Account> accounts) {
    if (r.note.isNotEmpty) return r.note;
    if (r.kind == TxnKind.transfer) {
      return 'Transfer to ${accounts[r.toAccountId]?.name ?? '—'}';
    }
    return category?.name ?? 'Recurring';
  }

  Future<void> _markPaid(RecurringRule r, String title) async {
    await ref.read(recurringRepositoryProvider).markPaid(r);
    Haptics.success();
    if (!mounted) return;
    AppToast.show(
      context,
      '$title marked as paid',
      icon: Icons.check_circle_rounded,
      tone: ToastTone.success,
      aboveNavBar: false,
    );
  }

  Future<void> _skipNext(RecurringRule r) async {
    final next = RecurringRepository.recurrenceOf(r).after(r.nextDue);
    final ok = await confirmSheet(
      context,
      title: 'Skip this payment?',
      message:
          'Due ${DateLabels.short(r.nextDue)} will be skipped. Next payment moves to ${DateLabels.short(next)}.',
      confirmLabel: 'Skip',
      destructive: false,
    );
    if (!ok || !mounted) return;
    await ref.read(recurringRepositoryProvider).skip(r);
    Haptics.selection();
    if (!mounted) return;
    AppToast.show(
      context,
      'Skipped · next due ${DateLabels.short(next)}',
      icon: Icons.skip_next_rounded,
      aboveNavBar: false,
    );
  }

  Future<void> _toggleActive(RecurringRule r) async {
    final nextActive = !r.active;
    await ref.read(recurringRepositoryProvider).setActive(r.id, nextActive);
    Haptics.selection();
    if (!mounted) return;
    AppToast.show(
      context,
      nextActive ? 'Recurring resumed' : 'Recurring paused',
      icon: nextActive ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded,
      aboveNavBar: false,
    );
  }

  Future<void> _more(RecurringRule r, String title) async {
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: title),
          OptionRow(
            leading: const Icon(Icons.edit_outlined),
            title: 'Edit details',
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          if (r.active) ...[
            OptionRow(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: 'Mark next payment as paid',
              subtitle: 'Records it today and moves to the next due date',
              onTap: () => Navigator.pop(ctx, 'pay'),
            ),
            OptionRow(
              leading: const Icon(Icons.skip_next_outlined),
              title: 'Skip next payment',
              onTap: () => Navigator.pop(ctx, 'skip'),
            ),
          ],
          OptionRow(
            leading: Icon(
              r.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
            ),
            title: r.active ? 'Pause recurring' : 'Resume recurring',
            onTap: () => Navigator.pop(ctx, 'toggle'),
          ),
          OptionRow(
            leading: Icon(Icons.delete_outline_rounded, color: ctx.palette.negative),
            title: 'Delete',
            destructive: true,
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await context.push('/recurring/${r.id}/edit');
      case 'pay':
        await _markPaid(r, title);
      case 'skip':
        await _skipNext(r);
      case 'toggle':
        await _toggleActive(r);
      case 'delete':
        final ok = await confirmSheet(
          context,
          title: 'Delete "$title"?',
          message: 'Transactions it already recorded stay in your history.',
        );
        if (!ok || !mounted) return;
        context.pop();
        await ref.read(recurringRepositoryProvider).delete(r.id);
        Haptics.medium();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rules = ref.watch(recurringProvider).value;
    final r = rules?.firstWhereOrNull((x) => x.id == widget.ruleId);
    if (r == null) return Scaffold(appBar: AppBar());

    final categories = ref.watch(categoryMapProvider);
    final accounts = ref.watch(accountMapProvider);
    final today = ref.watch(todayProvider);
    final money = ref.watch(moneyFormatProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final txns = ref.watch(recurringTxnsProvider(r.id)).value ?? const <Txn>[];
    final hidden = ref.watch(pendingDeletionsProvider);
    final visibleTxns = txns.where((t) => !hidden.contains(t.id)).toList();
    final views = TxnView.build(visibleTxns, categories, accounts);

    final category = categories[r.categoryId];
    final account = accounts[r.accountId];
    final toAccount = accounts[r.toAccountId];
    final title = _titleOf(r, category, accounts);
    final stats = RuleScheduleStats.compute(r, visibleTxns, today);

    final entityColorInt = category?.color ?? EntityColors.slate.light.toARGB32();
    final color = p.entity(entityColorInt);
    final iconKey = r.kind == TxnKind.transfer ? 'repeat' : (category?.icon ?? 'repeat');
    final overdue = r.active && r.nextDue.isBefore(today);
    final isIncome = r.kind == TxnKind.income;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => context.push('/recurring/${r.id}/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'More',
            onPressed: () => _more(r, title),
          ),
          const Gap(Insets.sm),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Hero section ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: stats.isEmi
                ? _EmiHero(
                    rule: r,
                    title: title,
                    iconKey: iconKey,
                    color: color,
                    stats: stats,
                    overdue: overdue,
                  )
                : _OngoingHero(
                    rule: r,
                    title: title,
                    iconKey: iconKey,
                    entityColorInt: entityColorInt,
                    category: category,
                    account: account,
                    toAccount: toAccount,
                    overdue: overdue,
                  ),
          ),

          // ── Summary stats card ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeSlideIn(
              index: 1,
              child: stats.isEmi
                  ? _EmiSummaryCard(stats: stats, color: color)
                  : _OngoingSummaryCard(stats: stats, isIncome: isIncome, year: today.year),
            ),
          ),

          // ── EMI Status Callout Banner ─────────────────────────────────────
          if (stats.isEmi)
            SliverToBoxAdapter(
              child: FadeSlideIn(
                index: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.page, Insets.md, Insets.page, 0),
                  child: AppCard(
                    color: stats.completed ? p.positiveFill.withValues(alpha: 0.14) : p.accentSoft,
                    child: Row(
                      children: [
                        Icon(
                          stats.completed
                              ? Icons.verified_rounded
                              : Icons.calendar_month_rounded,
                          color: stats.completed ? p.positive : p.accentText,
                        ),
                        const Gap(Insets.md),
                        Expanded(
                          child: Text(
                            stats.completed
                                ? 'All ${stats.totalCount} installments paid · Completed ${DateLabels.short(stats.lastInstallmentDate!)}.'
                                : hideAmounts
                                ? '${stats.remainingCount} installment${stats.remainingCount == 1 ? '' : 's'} left until ${DateLabels.monthYear(stats.lastInstallmentDate!)}.'
                                : '${stats.remainingCount} installment${stats.remainingCount == 1 ? '' : 's'} (${money.format(stats.remainingAmount)}) remaining · Ends ${DateLabels.monthYear(stats.lastInstallmentDate!)}.',
                            style: context.text.bodyMedium?.copyWith(
                              color: stats.completed ? p.positive : p.accentText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Quick Actions ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, Insets.lg, Insets.page, 0),
              child: r.active
                  ? Row(
                      children: [
                        Expanded(
                          child: AppButton.secondary(
                            label: 'Skip next',
                            icon: Icons.skip_next_rounded,
                            height: 46,
                            onPressed: () => _skipNext(r),
                          ),
                        ),
                        const Gap(Insets.md),
                        Expanded(
                          child: AppButton(
                            label: 'Mark as paid',
                            icon: Icons.check_circle_outline_rounded,
                            height: 46,
                            onPressed: () => _markPaid(r, title),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: AppButton.secondary(
                            label: 'Edit',
                            icon: Icons.edit_outlined,
                            height: 46,
                            onPressed: () => context.push('/recurring/${r.id}/edit'),
                          ),
                        ),
                        if (!stats.completed) ...[
                          const Gap(Insets.md),
                          Expanded(
                            child: AppButton(
                              label: 'Resume',
                              icon: Icons.play_arrow_rounded,
                              height: 46,
                              onPressed: () => _toggleActive(r),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),

          // ── Detailed Breakdown Card ───────────────────────────────────────
          SliverToBoxAdapter(
            child: SectionHeader(
              title: stats.isEmi ? 'EMI details' : 'Payment details',
              action: 'Edit',
              onAction: () => context.push('/recurring/${r.id}/edit'),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeSlideIn(
              index: 3,
              child: _DetailsBreakdownCard(
                rule: r,
                stats: stats,
                category: category,
                account: account,
                toAccount: toAccount,
                overdue: overdue,
              ),
            ),
          ),

          // ── EMI Installment Schedule OR Upcoming Occurrences ──────────────
          if (stats.isEmi && stats.installments.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'EMI schedule',
                trailing: Text(
                  '${stats.paidCount} / ${stats.totalCount} paid',
                  style: context.text.labelMedium?.copyWith(color: p.ink2),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: FadeSlideIn(
                index: 4,
                child: _EmiScheduleCard(
                  installments: stats.installments,
                  today: today,
                  color: color,
                  showAll: _showAllInstallments,
                  onToggleShowAll: () =>
                      setState(() => _showAllInstallments = !_showAllInstallments),
                ),
              ),
            ),
          ] else if (!stats.isEmi && stats.upcomingDates.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'Upcoming payments')),
            SliverToBoxAdapter(
              child: FadeSlideIn(
                index: 4,
                child: _UpcomingScheduleCard(
                  rule: r,
                  dates: stats.upcomingDates,
                  today: today,
                ),
              ),
            ),
          ],

          // ── Recorded Payment History ──────────────────────────────────────
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Payment history',
              trailing: Text('${views.length}', style: context.text.labelMedium),
            ),
          ),
          if (views.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.page),
                child: Text(
                  'Payments recorded for this recurring rule will appear here.',
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

// ── EMI Hero ───────────────────────────────────────────────────────────────

class _EmiHero extends StatelessWidget {
  const _EmiHero({
    required this.rule,
    required this.title,
    required this.iconKey,
    required this.color,
    required this.stats,
    required this.overdue,
  });

  final RecurringRule rule;
  final String title;
  final String iconKey;
  final Color color;
  final RuleScheduleStats stats;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pct = (stats.fraction * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
      child: Column(
        children: [
          FadeSlideIn(
            child: Center(
              child: ProgressRing(
                value: stats.fraction,
                color: stats.completed ? p.positive : color,
                track: (stats.completed ? p.positive : color).withValues(
                  alpha: p.isDark ? 0.2 : 0.14,
                ),
                size: 184,
                stroke: 15,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.of(iconKey),
                      color: stats.completed ? p.positive : color,
                      size: 28,
                    ),
                    const Gap(4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct.toDouble()),
                      duration: Motion.of(context, Motion.chart),
                      curve: Motion.emphasized,
                      builder: (context, v, _) =>
                          Text('${v.round()}%', style: context.text.displaySmall),
                    ),
                    Text(
                      '${stats.paidCount} of ${stats.totalCount} paid',
                      style: context.text.labelSmall?.copyWith(color: p.ink2, letterSpacing: 0),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Gap(Insets.lg),
          Text(title, style: context.text.headlineSmall, textAlign: TextAlign.center),
          const Gap(6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              MoneyText(
                rule.amount,
                style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                color: rule.kind == TxnKind.income ? p.positive : p.ink,
                tabular: false,
              ),
              const Gap(6),
              Text(
                '/ ${rule.every == 1 ? rule.frequency.unit : '${rule.every} ${rule.frequency.unit}s'}',
                style: context.text.bodyMedium?.copyWith(color: p.ink2),
              ),
            ],
          ),
          const Gap(8),
          _StatusBadges(rule: rule, isEmi: true, completed: stats.completed, overdue: overdue),
        ],
      ),
    );
  }
}

// ── Ongoing Hero ───────────────────────────────────────────────────────────

class _OngoingHero extends StatelessWidget {
  const _OngoingHero({
    required this.rule,
    required this.title,
    required this.iconKey,
    required this.entityColorInt,
    required this.category,
    required this.account,
    required this.toAccount,
    required this.overdue,
  });

  final RecurringRule rule;
  final String title;
  final String iconKey;
  final int entityColorInt;
  final Category? category;
  final Account? account;
  final Account? toAccount;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isIncome = rule.kind == TxnKind.income;
    final sub = rule.kind == TxnKind.transfer
        ? '${account?.name ?? '—'} → ${toAccount?.name ?? '—'}'
        : [category?.name, account?.name].whereType<String>().join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EntityIcon(icon: iconKey, color: entityColorInt, size: 56),
              const Gap(Insets.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.headlineSmall),
                    if (sub.isNotEmpty) ...[
                      const Gap(2),
                      Text(sub, style: context.text.bodySmall?.copyWith(color: p.ink2)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Gap(Insets.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              MoneyText(
                isIncome ? rule.amount : -rule.amount,
                sign: isIncome,
                color: isIncome ? p.positive : p.ink,
                style: context.text.displaySmall,
                tabular: false,
              ),
              const Gap(8),
              Text(
                rule.frequency.label(rule.every),
                style: context.text.titleMedium?.copyWith(color: p.ink2),
              ),
            ],
          ),
          const Gap(Insets.sm),
          _StatusBadges(rule: rule, isEmi: false, completed: false, overdue: overdue),
        ],
      ),
    );
  }
}

class _StatusBadges extends StatelessWidget {
  const _StatusBadges({
    required this.rule,
    required this.isEmi,
    required this.completed,
    required this.overdue,
  });

  final RecurringRule rule;
  final bool isEmi;
  final bool completed;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dueLabel = completed
        ? 'Completed'
        : !rule.active
        ? 'Paused'
        : overdue
        ? 'Overdue · due ${DateLabels.due(rule.nextDue)}'
        : 'Next due ${DateLabels.due(rule.nextDue)}';
    final dueColor = completed
        ? p.positive
        : !rule.active
        ? p.ink3
        : overdue
        ? p.negative
        : p.accentText;
    final dueBg = completed
        ? p.positiveFill.withValues(alpha: 0.14)
        : !rule.active
        ? p.surface2
        : overdue
        ? p.negativeFill.withValues(alpha: 0.14)
        : p.accentSoft;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (isEmi)
          _BadgePill(
            icon: Icons.timelapse_rounded,
            label: 'EMI / Fixed term',
            color: p.ink2,
            bg: p.surface2,
          ),
        _BadgePill(
          icon: completed
              ? Icons.check_circle_rounded
              : overdue
              ? Icons.error_outline_rounded
              : Icons.event_rounded,
          label: dueLabel,
          color: dueColor,
          bg: dueBg,
        ),
        _BadgePill(
          icon: rule.autoPost ? Icons.autorenew_rounded : Icons.touch_app_outlined,
          label: rule.autoPost ? 'Auto-pay' : 'Manual pay',
          color: p.ink2,
          bg: p.surface2,
        ),
      ],
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const Gap(5),
        Text(
          label,
          style: context.text.labelSmall?.copyWith(color: color, letterSpacing: 0.1),
        ),
      ],
    ),
  );
}

// ── Summary Cards ──────────────────────────────────────────────────────────

class _EmiSummaryCard extends StatelessWidget {
  const _EmiSummaryCard({required this.stats, required this.color});

  final RuleScheduleStats stats;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: Insets.page),
      child: Column(
        children: [
          Row(
            children: [
              _StatCol(
                label: 'Paid so far',
                amount: stats.paidAmount,
                sublabel: '${stats.paidCount} EMI${stats.paidCount == 1 ? '' : 's'}',
                color: p.positive,
              ),
              _StatCol(
                label: 'Remaining',
                amount: stats.remainingAmount,
                sublabel: '${stats.remainingCount} left',
                color: stats.remainingCount > 0 ? p.ink : p.ink3,
              ),
              _StatCol(
                label: 'Total EMI',
                amount: stats.totalAmount,
                sublabel: '${stats.totalCount} total',
              ),
            ],
          ),
          const Gap(Insets.md),
          MeterBar(
            value: stats.fraction,
            color: stats.completed ? p.positive : color,
            track: (stats.completed ? p.positive : color).withValues(alpha: p.isDark ? 0.2 : 0.14),
            height: 8,
          ),
        ],
      ),
    );
  }
}

class _OngoingSummaryCard extends StatelessWidget {
  const _OngoingSummaryCard({
    required this.stats,
    required this.isIncome,
    required this.year,
  });

  final RuleScheduleStats stats;
  final bool isIncome;
  final int year;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: Insets.page),
      child: Row(
        children: [
          _StatCol(
            label: isIncome ? 'Received so far' : 'Paid so far',
            amount: stats.paidAmount,
            sublabel: '${stats.paidCount} payment${stats.paidCount == 1 ? '' : 's'}',
            color: isIncome ? p.positive : p.ink,
          ),
          _StatCol(
            label: 'In $year',
            amount: stats.paidThisYear,
            sublabel: '${stats.paidThisYearCount} this yr',
          ),
          _StatCol(
            label: isIncome ? 'Yearly income' : 'Yearly cost',
            amount: stats.yearlyEquivalent,
            sublabel: '12 mo est.',
            color: p.ink2,
          ),
        ],
      ),
    );
  }
}

class _StatCol extends StatelessWidget {
  const _StatCol({
    required this.label,
    required this.amount,
    required this.sublabel,
    this.color,
  });

  final String label;
  final int amount;
  final String sublabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: context.text.labelSmall?.copyWith(color: p.ink3, letterSpacing: 0)),
          const Gap(4),
          MoneyText(
            amount,
            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            color: color ?? p.ink,
            tabular: false,
          ),
          const Gap(2),
          Text(
            sublabel,
            style: context.text.labelSmall?.copyWith(color: p.ink2, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

// ── Details Breakdown Card ─────────────────────────────────────────────────

class _DetailsBreakdownCard extends ConsumerWidget {
  const _DetailsBreakdownCard({
    required this.rule,
    required this.stats,
    required this.category,
    required this.account,
    required this.toAccount,
    required this.overdue,
  });

  final RecurringRule rule;
  final RuleScheduleStats stats;
  final Category? category;
  final Account? account;
  final Account? toAccount;
  final bool overdue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final money = ref.watch(moneyFormatProvider);
    final isTransfer = rule.kind == TxnKind.transfer;
    final nextText = stats.completed
        ? 'All paid'
        : !rule.active
        ? 'Paused'
        : '${DateLabels.short(rule.nextDue)} (${DateLabels.due(rule.nextDue)})';

    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: Insets.page),
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 6),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.payments_outlined,
            label: stats.isEmi ? 'Installment amount' : 'Payment amount',
            trailing: MoneyText(
              rule.amount,
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Divider(color: p.hairline, height: 1),
          _InfoRow(
            icon: Icons.repeat_rounded,
            label: 'Frequency',
            value: rule.frequency.label(rule.every),
          ),
          Divider(color: p.hairline, height: 1),
          if (stats.isEmi) ...[
            _InfoRow(
              icon: Icons.donut_large_rounded,
              label: 'Installments',
              value:
                  '${stats.paidCount} paid · ${stats.remainingCount} left (${stats.totalCount} total)',
            ),
            Divider(color: p.hairline, height: 1),
            _InfoRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Total EMI payable',
              trailing: MoneyText(
                stats.totalAmount,
                style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Divider(color: p.hairline, height: 1),
            _InfoRow(
              icon: Icons.check_circle_outline_rounded,
              label: 'Total paid so far',
              trailing: MoneyText(
                stats.paidAmount,
                color: p.positive,
                style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Divider(color: p.hairline, height: 1),
            _InfoRow(
              icon: Icons.pending_actions_rounded,
              label: 'Balance remaining',
              trailing: MoneyText(
                stats.remainingAmount,
                style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Divider(color: p.hairline, height: 1),
          ] else ...[
            _InfoRow(
              icon: Icons.calculate_outlined,
              label: 'Monthly / Yearly',
              value: '${money.format(stats.monthlyEquivalent)}/mo · ${money.format(stats.yearlyEquivalent)}/yr',
            ),
            Divider(color: p.hairline, height: 1),
          ],
          _InfoRow(
            icon: Icons.event_rounded,
            label: 'Next due date',
            value: nextText,
            valueColor: overdue ? p.negative : null,
          ),
          Divider(color: p.hairline, height: 1),
          _InfoRow(
            icon: Icons.play_circle_outline_rounded,
            label: stats.isEmi ? 'First EMI date' : 'Started on',
            value: DateLabels.short(rule.startDate),
          ),
          Divider(color: p.hairline, height: 1),
          _InfoRow(
            icon: Icons.event_busy_outlined,
            label: stats.isEmi ? 'Last EMI date' : 'Ends',
            value: stats.isEmi
                ? DateLabels.short(stats.lastInstallmentDate!)
                : 'Ongoing (Never)',
          ),
          Divider(color: p.hairline, height: 1),
          if (!isTransfer && category != null) ...[
            _InfoRow(
              icon: Icons.category_outlined,
              label: 'Category',
              value: category!.name,
              onTap: () => context.push('/categories/${category!.id}'),
            ),
            Divider(color: p.hairline, height: 1),
          ],
          _InfoRow(
            icon: Icons.account_balance_rounded,
            label: isTransfer ? 'Transfer accounts' : 'Account',
            value: isTransfer
                ? '${account?.name ?? '—'} → ${toAccount?.name ?? '—'}'
                : (account?.name ?? '—'),
            onTap: account != null ? () => context.push('/accounts/${account!.id}') : null,
          ),
          Divider(color: p.hairline, height: 1),
          _InfoRow(
            icon: Icons.autorenew_rounded,
            label: 'Recording mode',
            value: rule.autoPost ? 'Automatic on due date' : 'Confirm manually',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 19, color: p.ink3),
          const Gap(Insets.md),
          Text(label, style: context.text.bodyMedium?.copyWith(color: p.ink2)),
          const Gap(Insets.md),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (trailing != null)
                  Flexible(child: trailing!)
                else if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      style: context.text.titleSmall?.copyWith(color: valueColor ?? p.ink),
                    ),
                  ),
                if (onTap != null) ...[
                  const Gap(2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.ink3),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return onTap != null ? Pressable(onTap: onTap, child: row) : row;
  }
}

// ── EMI Installment Schedule Card ──────────────────────────────────────────

class _EmiScheduleCard extends StatelessWidget {
  const _EmiScheduleCard({
    required this.installments,
    required this.today,
    required this.color,
    required this.showAll,
    required this.onToggleShowAll,
  });

  final List<EmiInstallment> installments;
  final DateTime today;
  final Color color;
  final bool showAll;
  final VoidCallback onToggleShowAll;

  List<EmiInstallment> _visibleSlice() {
    if (showAll || installments.length <= 6) return installments;
    final nextIdx = installments.indexWhere((e) => e.isNext);
    if (nextIdx == -1) {
      // All paid or paused: show last 6
      return installments.sublist(math.max(0, installments.length - 6));
    }
    // Show up to 2 recently paid + next + up to 3 upcoming
    final start = math.max(0, nextIdx - 2);
    final end = math.min(installments.length, start + 6);
    return installments.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final visible = _visibleSlice();
    final canToggle = installments.length > 6;

    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: Insets.page),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) Divider(color: p.hairline, height: 1, indent: Insets.lg, endIndent: Insets.lg),
            _InstallmentRow(item: visible[i], today: today, color: color),
          ],
          if (canToggle) ...[
            Divider(color: p.hairline, height: 1),
            Pressable(
              onTap: onToggleShowAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      showAll
                          ? 'Show fewer installments'
                          : 'View all ${installments.length} installments',
                      style: context.text.labelMedium?.copyWith(color: p.accentText),
                    ),
                    const Gap(4),
                    Icon(
                      showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: p.accentText,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({
    required this.item,
    required this.today,
    required this.color,
  });

  final EmiInstallment item;
  final DateTime today;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final overdue = !item.isPaid && item.date.isBefore(today);
    final statusText = item.isPaid
        ? 'Paid · ${DateLabels.short(item.date)}'
        : overdue
        ? 'Overdue · ${DateLabels.short(item.date)}'
        : item.isNext
        ? 'Next due ${DateLabels.due(item.date)} · ${DateLabels.short(item.date)}'
        : DateLabels.short(item.date);

    final badgeColor = item.isPaid
        ? p.positive
        : overdue
        ? p.negative
        : item.isNext
        ? color
        : p.ink3;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: item.isPaid || item.isNext ? 0.15 : 0.08),
              shape: BoxShape.circle,
            ),
            child: item.isPaid
                ? Icon(Icons.check_rounded, size: 18, color: p.positive)
                : Text(
                    '#${item.number}',
                    style: context.text.labelSmall?.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
          ),
          const Gap(Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Installment #${item.number}',
                      style: context.text.titleSmall?.copyWith(
                        color: item.isPaid ? p.ink2 : p.ink,
                      ),
                    ),
                    if (item.isNext) ...[
                      const Gap(6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (overdue ? p.negative : color).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          overdue ? 'Overdue' : 'Next',
                          style: context.text.labelSmall?.copyWith(
                            color: overdue ? p.negative : color,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const Gap(2),
                Text(
                  statusText,
                  style: context.text.bodySmall?.copyWith(
                    color: overdue ? p.negative : (item.isPaid ? p.positive : p.ink2),
                  ),
                ),
              ],
            ),
          ),
          MoneyText(
            item.amount,
            color: item.isPaid ? p.positive : p.ink,
            style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    if (item.txn != null) {
      return Pressable(
        onTap: () => context.push('/txn/${item.txn!.id}'),
        child: row,
      );
    }
    return row;
  }
}

// ── Ongoing Upcoming Schedule Card ─────────────────────────────────────────

class _UpcomingScheduleCard extends StatelessWidget {
  const _UpcomingScheduleCard({
    required this.rule,
    required this.dates,
    required this.today,
  });

  final RecurringRule rule;
  final List<DateTime> dates;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isIncome = rule.kind == TxnKind.income;
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: Insets.page),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < dates.length; i++) ...[
            if (i > 0)
              Divider(color: p.hairline, height: 1, indent: Insets.lg, endIndent: Insets.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (i == 0 ? p.accent : p.ink3).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.event_rounded,
                      size: 17,
                      color: i == 0 ? p.accentText : p.ink2,
                    ),
                  ),
                  const Gap(Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateLabels.day(dates[i], now: today), style: context.text.titleSmall),
                        Text(
                          '${DateLabels.short(dates[i])} · ${DateLabels.due(dates[i], now: today)}',
                          style: context.text.bodySmall?.copyWith(color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                  MoneyText(
                    isIncome ? rule.amount : -rule.amount,
                    sign: isIncome,
                    color: isIncome ? p.positive : p.ink,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
