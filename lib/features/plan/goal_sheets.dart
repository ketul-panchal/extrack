import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/celebration.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/pickers.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/segmented.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';

/// Create or edit a savings goal. Resolves to the goal id on save.
Future<int?> showGoalEditor(BuildContext context, {Goal? goal}) =>
    showAppSheet<int>(context, builder: (_) => _GoalEditor(goal: goal));

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor({required this.goal});

  final Goal? goal;

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  late final _name = TextEditingController(text: widget.goal?.name ?? '');
  late final _target = TextEditingController(
    text: widget.goal == null ? '' : ref.read(moneyFormatProvider).toInput(widget.goal!.target),
  );
  late String _icon = widget.goal?.icon ?? 'flag';
  late int _color = widget.goal?.color ?? EntityColors.aqua.light.toARGB32();
  late DateTime? _deadline = widget.goal?.deadline;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  bool get _valid {
    final t = ref.read(moneyFormatProvider).parse(_target.text);
    return _name.text.trim().isNotEmpty && t != null && t > 0;
  }

  Future<void> _pickIcon() async {
    final key = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Icon'),
          Flexible(
            child: IconPickerGrid(
              selected: _icon,
              color: _color,
              onChanged: (k) => Navigator.pop(ctx, k),
            ),
          ),
        ],
      ),
    );
    if (key != null) setState(() => _icon = key);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(now.year, now.month + 6, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 30),
      helpText: 'Reach this goal by',
    );
    if (d != null) setState(() => _deadline = d);
  }

  Future<void> _save() async {
    if (!_valid) {
      Haptics.error();
      return;
    }
    final target = ref.read(moneyFormatProvider).parse(_target.text)!;
    final repo = ref.read(goalRepositoryProvider);
    int id;
    if (widget.goal != null) {
      await repo.save(
        widget.goal!.copyWith(
          name: _name.text.trim(),
          target: target,
          icon: _icon,
          color: _color,
          deadline: Value(_deadline),
        ),
      );
      id = widget.goal!.id;
    } else {
      id = await repo.add(
        name: _name.text,
        target: target,
        icon: _icon,
        color: _color,
        deadline: _deadline,
      );
    }
    Haptics.success();
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final money = ref.watch(moneyFormatProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.goal == null ? 'New goal' : 'Edit goal', style: context.text.headlineSmall),
          const Gap(Insets.lg),
          Row(
            children: [
              Pressable(
                onTap: _pickIcon,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    EntityIcon(icon: _icon, color: _color, size: 56),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                        child: Icon(Icons.edit_rounded, size: 14, color: p.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(Insets.lg),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: widget.goal == null,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  style: context.text.titleMedium,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Trip to Japan',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const Gap(Insets.lg),
          TextField(
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: context.text.titleLarge?.tabular,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Target amount',
              prefixText: money.style.symbolFirst ? '${money.currency.symbol} ' : null,
              suffixText: money.style.symbolFirst ? null : money.currency.symbol,
            ),
          ),
          const Gap(Insets.md),
          Row(
            children: [
              SelectChip(
                label: _deadline == null ? 'No deadline' : 'By ${DateLabels.short(_deadline!)}',
                icon: Icons.event_rounded,
                selected: _deadline != null,
                dense: true,
                onTap: _pickDeadline,
              ),
              if (_deadline != null) ...[
                const Gap(Insets.sm),
                CircleIconButton(
                  icon: Icons.close_rounded,
                  size: 34,
                  iconSize: 16,
                  tooltip: 'Remove deadline',
                  onPressed: () => setState(() => _deadline = null),
                ),
              ],
            ],
          ),
          const Gap(Insets.xl),
          Text('Color', style: context.text.labelMedium?.copyWith(color: p.ink3)),
          const Gap(Insets.sm),
          ColorSwatchPicker(selected: _color, onChanged: (c) => setState(() => _color = c)),
          const Gap(Insets.xxl),
          AppButton(
            label: widget.goal == null ? 'Create goal' : 'Save',
            onPressed: _valid ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// Put money toward a goal, or take some out.
Future<void> showGoalMoneySheet(
  BuildContext context,
  GoalProgress progress, {
  bool withdraw = false,
}) => showAppSheet<void>(
  context,
  builder: (_) => _GoalMoney(progress: progress, withdraw: withdraw),
);

class _GoalMoney extends ConsumerStatefulWidget {
  const _GoalMoney({required this.progress, required this.withdraw});

  final GoalProgress progress;
  final bool withdraw;

  @override
  ConsumerState<_GoalMoney> createState() => _GoalMoneyState();
}

class _GoalMoneyState extends ConsumerState<_GoalMoney> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late bool _withdraw = widget.withdraw;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final money = ref.read(moneyFormatProvider);
    final value = money.parse(_amount.text);
    if (value == null || value <= 0) {
      Haptics.error();
      return;
    }
    final g = widget.progress.goal;
    final repo = ref.read(goalRepositoryProvider);
    final signed = _withdraw ? -math.min(value, widget.progress.saved) : value;
    if (signed == 0) {
      Haptics.error();
      return;
    }
    await repo.addEntry(g.id, signed, note: _note.text);
    final saved = widget.progress.saved + signed;
    final reachedNow = saved >= g.target && g.completedAt == null;
    if (reachedNow) {
      await repo.setCompleted(g.id, clock.now());
    } else if (saved < g.target && g.completedAt != null) {
      await repo.setCompleted(g.id, null);
    }
    Haptics.success();
    if (!mounted) return;
    if (reachedNow) {
      Celebration.show(context);
      AppToast.show(
        context,
        'You reached "${g.name}"!',
        icon: Icons.celebration_rounded,
        tone: ToastTone.success,
        aboveNavBar: true,
      );
    } else {
      AppToast.show(
        context,
        _withdraw ? 'Withdrawn from ${g.name}' : 'Added to ${g.name}',
        icon: Icons.check_circle_rounded,
        tone: ToastTone.success,
        aboveNavBar: true,
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final money = ref.watch(moneyFormatProvider);
    final g = widget.progress.goal;
    final remaining = widget.progress.remaining;
    // Friendly quick amounts: a tenth and a quarter of the target, and what's left.
    int round(double v) {
      final unit = money.unit;
      final units = v / unit;
      final step = units >= 10000 ? 1000 : (units >= 1000 ? 100 : (units >= 100 ? 10 : 1));
      return ((units / step).round() * step * unit).toInt();
    }

    final quick = <int>{
      if (!_withdraw && g.target > 0) round(g.target / 10),
      if (!_withdraw && g.target > 0) round(g.target / 4),
      if (!_withdraw && remaining > 0) remaining,
      if (_withdraw && widget.progress.saved > 0) widget.progress.saved,
    }.where((v) => v > 0).toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EntityIcon(icon: g.icon, color: g.color, size: 44),
              const Gap(Insets.md),
              Expanded(child: Text(g.name, style: context.text.headlineSmall)),
            ],
          ),
          const Gap(Insets.lg),
          SegmentedTabs<bool>(
            values: const [false, true],
            selected: _withdraw,
            labelOf: (w) => w ? 'Withdraw' : 'Add money',
            onChanged: (w) => setState(() => _withdraw = w),
          ),
          const Gap(Insets.lg),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: context.text.headlineMedium?.tabular,
            decoration: InputDecoration(
              hintText: '0',
              prefixText: money.style.symbolFirst ? '${money.currency.symbol} ' : null,
              suffixText: money.style.symbolFirst ? null : money.currency.symbol,
            ),
            onSubmitted: (_) => _save(),
          ),
          if (quick.isNotEmpty) ...[
            const Gap(Insets.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in quick)
                  SelectChip(
                    label: q == remaining && !_withdraw
                        ? 'Rest: ${money.format(q)}'
                        : (_withdraw ? 'All: ${money.format(q)}' : money.format(q)),
                    dense: true,
                    selected: false,
                    onTap: () => setState(() => _amount.text = money.toInput(q)),
                  ),
              ],
            ),
          ],
          const Gap(Insets.md),
          TextField(
            controller: _note,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Note (optional)', counterText: ''),
          ),
          const Gap(Insets.xl),
          AppButton(
            label: _withdraw ? 'Withdraw' : 'Add to goal',
            variant: _withdraw ? ButtonVariant.secondary : ButtonVariant.primary,
            onPressed: _save,
          ),
          const Gap(Insets.xs),
          Center(
            child: Text(
              'Goals track money you set aside. Account balances don\'t change.',
              style: context.text.bodySmall?.copyWith(color: p.ink3),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
