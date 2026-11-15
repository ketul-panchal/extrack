import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_icons.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/plan/goal_sheets.dart';
import 'package:spent/features/plan/plan_screen.dart' show monthsUntil;
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/progress.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final int goalId;

  Future<void> _more(BuildContext context, WidgetRef ref, Goal goal) async {
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: goal.name),
          OptionRow(
            leading: const Icon(Icons.edit_outlined),
            title: 'Edit goal',
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          OptionRow(
            leading: Icon(goal.completedAt == null ? Icons.task_alt_rounded : Icons.replay_rounded),
            title: goal.completedAt == null ? 'Mark as complete' : 'Reopen goal',
            onTap: () => Navigator.pop(ctx, 'complete'),
          ),
          OptionRow(
            leading: Icon(Icons.delete_outline_rounded, color: ctx.palette.negative),
            title: 'Delete goal',
            destructive: true,
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    final repo = ref.read(goalRepositoryProvider);
    switch (action) {
      case 'edit':
        await showGoalEditor(context, goal: goal);
      case 'complete':
        await repo.setCompleted(goal.id, goal.completedAt == null ? DateTime.now() : null);
        Haptics.success();
      case 'delete':
        final ok = await confirmSheet(
          context,
          title: 'Delete "${goal.name}"?',
          message: 'The goal and its history will be removed. Your accounts are not affected.',
        );
        if (!ok || !context.mounted) return;
        context.pop();
        await repo.delete(goal.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final goals = ref.watch(goalsProvider).value;
    final progress = goals?.firstWhereOrNull((g) => g.goal.id == goalId);
    final entries = ref.watch(goalEntriesProvider(goalId)).value ?? const <GoalEntry>[];
    final money = ref.watch(moneyFormatProvider);
    if (progress == null) return Scaffold(appBar: AppBar());
    final g = progress.goal;
    final color = p.entity(g.color);
    final now = DateTime.now();
    final months = g.deadline == null ? null : monthsUntil(now, g.deadline!);
    final pct = (progress.fraction * 100).floor();

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'More',
            onPressed: () => _more(context, ref, g),
          ),
          const Gap(Insets.sm),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Insets.xxl),
        children: [
          FadeSlideIn(
            child: Center(
              child: ProgressRing(
                value: progress.fraction,
                color: color,
                track: color.withValues(alpha: p.isDark ? 0.2 : 0.14),
                size: 196,
                stroke: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.of(g.icon), color: color, size: 30),
                    const Gap(4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct.toDouble()),
                      duration: Motion.of(context, Motion.chart),
                      curve: Motion.emphasized,
                      builder: (context, v, _) =>
                          Text('${v.round()}%', style: context.text.displaySmall),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Gap(Insets.lg),
          Center(child: Text(g.name, style: context.text.headlineSmall)),
          if (g.completedAt != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Completed ${DateLabels.short(g.completedAt!)}',
                  style: context.text.labelMedium?.copyWith(color: p.positive),
                ),
              ),
            ),
          const Gap(Insets.xl),
          FadeSlideIn(
            index: 1,
            child: AppCard(
              margin: const EdgeInsets.symmetric(horizontal: Insets.page),
              child: Row(
                children: [
                  _Stat(label: 'Saved', amount: progress.saved),
                  _Stat(label: 'Target', amount: g.target),
                  _Stat(label: 'To go', amount: progress.remaining),
                ],
              ),
            ),
          ),
          if (!progress.reached && months != null) ...[
            const Gap(Insets.md),
            FadeSlideIn(
              index: 2,
              child: AppCard(
                margin: const EdgeInsets.symmetric(horizontal: Insets.page),
                color: p.accentSoft,
                child: Row(
                  children: [
                    Icon(Icons.event_available_rounded, color: p.accentText),
                    const Gap(Insets.md),
                    Expanded(
                      child: Text(
                        months <= 0
                            ? 'The deadline (${DateLabels.short(g.deadline!)}) has passed.'
                            : ref.watch(hideAmountsProvider)
                            ? 'Save a little each month to get there by ${DateLabels.monthYear(g.deadline!)}.'
                            : 'Save ${money.format((progress.remaining / months).ceil())} a month to reach it by ${DateLabels.monthYear(g.deadline!)}.',
                        style: context.text.bodyMedium?.copyWith(
                          color: p.accentText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Gap(Insets.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.page),
            child: Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Withdraw',
                    icon: Icons.remove_rounded,
                    onPressed: progress.saved > 0
                        ? () => showGoalMoneySheet(context, progress, withdraw: true)
                        : null,
                  ),
                ),
                const Gap(Insets.md),
                Expanded(
                  child: AppButton(
                    label: 'Add money',
                    icon: Icons.add_rounded,
                    onPressed: () => showGoalMoneySheet(context, progress),
                  ),
                ),
              ],
            ),
          ),
          SectionHeader(
            title: 'History',
            trailing: Text('${entries.length}', style: context.text.labelMedium),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page),
              child: Text(
                'Money you put aside will show up here.',
                style: context.text.bodyMedium?.copyWith(color: p.ink3),
              ),
            )
          else
            AppCard(
              margin: const EdgeInsets.symmetric(horizontal: Insets.page),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final e in entries)
                    Dismissible(
                      key: ValueKey('entry-${e.id}'),
                      direction: DismissDirection.endToStart,
                      background: ColoredBox(
                        color: p.negativeFill,
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: Insets.xl),
                            child: Icon(Icons.delete_outline_rounded, color: Colors.white),
                          ),
                        ),
                      ),
                      onDismissed: (_) async {
                        final repo = ref.read(goalRepositoryProvider);
                        await repo.deleteEntry(e.id);
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            'Entry removed',
                            icon: Icons.delete_outline_rounded,
                            actionLabel: 'Undo',
                            onAction: () =>
                                repo.addEntry(e.goalId, e.amount, date: e.date, note: e.note),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: (e.amount >= 0 ? p.positiveFill : p.ink3).withValues(
                                  alpha: 0.14,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                e.amount >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                                size: 17,
                                color: e.amount >= 0 ? p.positive : p.ink2,
                              ),
                            ),
                            const Gap(Insets.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.note.isNotEmpty
                                        ? e.note
                                        : (e.amount >= 0 ? 'Added' : 'Withdrawn'),
                                    style: context.text.titleSmall,
                                  ),
                                  Text(DateLabels.day(e.date), style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            MoneyText(
                              e.amount,
                              sign: true,
                              color: e.amount >= 0 ? p.positive : p.ink,
                              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.ink3)),
        const Gap(4),
        MoneyText(
          amount,
          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          tabular: false,
        ),
      ],
    ),
  );
}
