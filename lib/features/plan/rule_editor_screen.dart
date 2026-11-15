import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/core/time/recurrence.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/pickers/picker_sheets.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/segmented.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';

class RuleEditorScreen extends ConsumerStatefulWidget {
  const RuleEditorScreen({super.key, this.ruleId});

  final int? ruleId;

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  TxnKind _kind = TxnKind.expense;
  int? _categoryId;
  late int? _accountId = ref.read(settingsProvider).defaultAccountId;
  int? _toAccountId;
  Frequency _frequency = Frequency.monthly;
  int _every = 1;
  DateTime _next = dateOnly(DateTime.now());
  DateTime? _end;
  bool _autoPost = true;
  bool _active = true;
  RecurringRule? _original;
  bool _saving = false;

  bool get _editing => widget.ruleId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) unawaited(_load());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await ref.read(recurringRepositoryProvider).byId(widget.ruleId!);
    if (!mounted) return;
    if (r == null) {
      context.pop();
      return;
    }
    setState(() {
      _original = r;
      _kind = r.kind;
      _amount.text = ref.read(moneyFormatProvider).toInput(r.amount);
      _note.text = r.note;
      _categoryId = r.categoryId;
      _accountId = r.accountId;
      _toAccountId = r.toAccountId;
      _frequency = r.frequency;
      _every = r.every;
      _next = r.nextDue;
      _end = r.endDate;
      _autoPost = r.autoPost;
      _active = r.active;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final money = ref.read(moneyFormatProvider);
    final amount = money.parse(_amount.text);
    final accounts = ref.read(activeAccountsProvider);
    final accountId = _accountId ?? accounts.firstOrNull?.id;
    String? problem;
    if (amount == null || amount <= 0) problem = 'Enter an amount';
    if (accountId == null) problem = 'Add an account first';
    if (_kind == TxnKind.transfer && (_toAccountId == null || _toAccountId == accountId)) {
      problem = 'Choose two different accounts';
    }
    if (_kind != TxnKind.transfer && _categoryId == null) problem = 'Pick a category';
    if (_end != null && _end!.isBefore(_next)) problem = 'The end date is before the next date';
    if (problem != null) {
      Haptics.error();
      AppToast.show(context, problem, icon: Icons.info_outline_rounded);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(recurringRepositoryProvider);
    final transfer = _kind == TxnKind.transfer;
    final o = _original;
    if (o != null) {
      final scheduleMoved = dateOnly(o.nextDue) != _next || o.frequency != _frequency;
      await repo.save(
        o.copyWith(
          kind: _kind,
          amount: amount,
          accountId: accountId,
          categoryId: Value(transfer ? null : _categoryId),
          toAccountId: Value(transfer ? _toAccountId : null),
          note: _note.text.trim(),
          frequency: _frequency,
          every: _every,
          startDate: scheduleMoved ? _next : o.startDate,
          nextDue: _next,
          endDate: Value(_end),
          autoPost: _autoPost,
          active: _active,
        ),
      );
    } else {
      await repo.add(
        kind: _kind,
        amount: amount!,
        accountId: accountId!,
        categoryId: _categoryId,
        toAccountId: _toAccountId,
        note: _note.text,
        frequency: _frequency,
        every: _every,
        startDate: _next,
        nextDue: _next,
        endDate: _end,
        autoPost: _autoPost,
      );
    }
    final posted = await repo.processDue(DateTime.now());
    Haptics.success();
    if (!mounted) return;
    AppToast.show(
      context,
      posted > 0
          ? 'Saved · $posted payment${posted == 1 ? '' : 's'} recorded'
          : (o == null ? 'Recurring saved' : 'Changes saved'),
      icon: Icons.check_circle_rounded,
      tone: ToastTone.success,
      aboveNavBar: true,
    );
    context.pop();
  }

  Future<void> _delete() async {
    final o = _original;
    if (o == null) return;
    final ok = await confirmSheet(
      context,
      title: 'Delete this recurring payment?',
      message: 'Transactions it already recorded stay in your history.',
    );
    if (!ok || !mounted) return;
    await ref.read(recurringRepositoryProvider).delete(o.id);
    Haptics.medium();
    if (!mounted) return;
    context.pop();
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _pickDate({required bool end}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: end ? (_end ?? _next.add(const Duration(days: 365))) : _next,
      firstDate: end ? _next : DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
      helpText: end ? 'Last payment on or before' : 'Next payment date',
    );
    if (d == null) return;
    setState(() => end ? _end = dateOnly(d) : _next = dateOnly(d));
  }

  void _setInstallmentCount(int count) {
    if (count < 1) return;
    final rec = Recurrence(frequency: _frequency, every: _every, anchor: _next);
    var d = dateOnly(_next);
    for (var i = 1; i < count; i++) {
      d = rec.after(d);
    }
    setState(() => _end = d);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final money = ref.watch(moneyFormatProvider);
    final categories = ref.watch(categoryMapProvider);
    final accounts = ref.watch(accountMapProvider);
    final active = ref.watch(activeAccountsProvider);
    final accountId = _accountId ?? active.firstOrNull?.id;
    final category = categories[_categoryId];
    final recurrence = Recurrence(frequency: _frequency, every: _every, anchor: _next);
    final preview = recurrence
        .occurrences(_next, DateTime(_next.year + 5), limit: 4)
        .where((d) => _end == null || !d.isAfter(_end!))
        .toList();
    final emiOccurrences = _end != null && !_end!.isBefore(_next)
        ? recurrence.occurrences(_next, _end!, limit: 600)
        : const <DateTime>[];
    final parsedAmount = money.parse(_amount.text) ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.pop()),
        title: Text(_editing ? 'Recurring' : 'New recurring'),
        actions: [
          if (_editing)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: p.negative),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
          const Gap(Insets.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, Insets.xxl),
        children: [
          SegmentedTabs<TxnKind>(
            values: TxnKind.values,
            selected: _kind,
            labelOf: (k) => k.label,
            onChanged: (k) => setState(() {
              if ((k == TxnKind.income) != (_kind == TxnKind.income) || k == TxnKind.transfer) {
                _categoryId = null;
              }
              _kind = k;
            }),
          ),
          const Gap(Insets.xl),
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: context.text.headlineMedium?.tabular,
            decoration: InputDecoration(
              hintText: 'Amount',
              prefixText: money.style.symbolFirst ? '${money.currency.symbol} ' : null,
              suffixText: money.style.symbolFirst ? null : money.currency.symbol,
            ),
          ),
          const Gap(Insets.md),
          TextField(
            controller: _note,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Name, e.g. Netflix or Rent',
              counterText: '',
            ),
          ),
          const Gap(Insets.lg),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (_kind != TxnKind.transfer)
                  OptionRow(
                    title: 'Category',
                    leading: category == null
                        ? Icon(Icons.category_outlined, color: p.ink3)
                        : EntityIcon(icon: category.icon, color: category.color, size: 32),
                    trailing: _Value(category?.name ?? 'Choose'),
                    onTap: () async {
                      final id = await pickCategory(
                        context,
                        kind: _kind == TxnKind.income ? CategoryKind.income : CategoryKind.expense,
                        selected: _categoryId,
                      );
                      if (id != null) setState(() => _categoryId = id);
                    },
                  ),
                OptionRow(
                  title: _kind == TxnKind.transfer ? 'From' : 'Account',
                  leading: accounts[accountId] == null
                      ? Icon(Icons.account_balance_wallet_outlined, color: p.ink3)
                      : EntityIcon(
                          icon: accounts[accountId]!.icon,
                          color: accounts[accountId]!.color,
                          size: 32,
                        ),
                  trailing: _Value(accounts[accountId]?.name ?? 'Choose'),
                  onTap: () async {
                    final id = await pickAccount(context, selected: accountId);
                    if (id != null) setState(() => _accountId = id);
                  },
                ),
                if (_kind == TxnKind.transfer)
                  OptionRow(
                    title: 'To',
                    leading: accounts[_toAccountId] == null
                        ? Icon(Icons.account_balance_wallet_outlined, color: p.ink3)
                        : EntityIcon(
                            icon: accounts[_toAccountId]!.icon,
                            color: accounts[_toAccountId]!.color,
                            size: 32,
                          ),
                    trailing: _Value(accounts[_toAccountId]?.name ?? 'Choose'),
                    onTap: () async {
                      final id = await pickAccount(
                        context,
                        selected: _toAccountId,
                        exclude: accountId,
                      );
                      if (id != null) setState(() => _toAccountId = id);
                    },
                  ),
              ],
            ),
          ),
          const Gap(Insets.xl),
          Text('Repeats', style: context.text.labelMedium?.copyWith(color: p.ink3)),
          const Gap(Insets.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in Frequency.values)
                SelectChip(
                  label: f.label(1),
                  dense: true,
                  selected: _frequency == f,
                  onTap: () => setState(() => _frequency = f),
                ),
            ],
          ),
          const Gap(Insets.md),
          AppCard(
            padding: const EdgeInsets.fromLTRB(Insets.lg, 6, 6, 6),
            child: Row(
              children: [
                Expanded(child: Text('Every', style: context.text.titleSmall)),
                CircleIconButton(
                  icon: Icons.remove_rounded,
                  size: 36,
                  iconSize: 18,
                  onPressed: _every > 1 ? () => setState(() => _every--) : null,
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    '$_every ${_frequency.unit}${_every == 1 ? '' : 's'}',
                    textAlign: TextAlign.center,
                    style: context.text.titleSmall,
                  ),
                ),
                CircleIconButton(
                  icon: Icons.add_rounded,
                  size: 36,
                  iconSize: 18,
                  onPressed: _every < 30 ? () => setState(() => _every++) : null,
                ),
              ],
            ),
          ),
          const Gap(Insets.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                OptionRow(
                  title: 'Next payment',
                  leading: Icon(Icons.event_rounded, color: p.ink2),
                  trailing: _Value(DateLabels.chip(_next)),
                  onTap: () => _pickDate(end: false),
                ),
                OptionRow(
                  title: 'Ends (EMI / Fixed term)',
                  leading: Icon(Icons.event_busy_outlined, color: p.ink2),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Value(_end == null ? 'Never (Ongoing)' : DateLabels.short(_end!)),
                      if (_end != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() => _end = null),
                        ),
                    ],
                  ),
                  onTap: () => _pickDate(end: true),
                ),
              ],
            ),
          ),
          const Gap(Insets.md),
          Text(
            'EMI / Installment presets',
            style: context.text.labelMedium?.copyWith(color: p.ink3),
          ),
          const Gap(Insets.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SelectChip(
                label: 'Ongoing',
                dense: true,
                selected: _end == null,
                onTap: () => setState(() => _end = null),
              ),
              for (final n in const [3, 6, 9, 12, 18, 24])
                SelectChip(
                  label: '$n EMIs',
                  dense: true,
                  selected: _end != null && emiOccurrences.length == n,
                  onTap: () => _setInstallmentCount(n),
                ),
            ],
          ),
          if (_end != null && emiOccurrences.isNotEmpty) ...[
            const Gap(Insets.md),
            AppCard(
              color: p.accentSoft,
              padding: const EdgeInsets.fromLTRB(Insets.lg, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.timelapse_rounded, color: p.accentText),
                  const Gap(Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${emiOccurrences.length} installment${emiOccurrences.length == 1 ? '' : 's'} remaining',
                          style: context.text.titleSmall?.copyWith(color: p.accentText),
                        ),
                        const Gap(2),
                        if (parsedAmount > 0)
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'Total payable: '),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: MoneyText(
                                    parsedAmount * emiOccurrences.length,
                                    style: context.text.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    color: p.accentText,
                                    tabular: false,
                                  ),
                                ),
                                TextSpan(
                                  text: ' · Ends ${DateLabels.short(emiOccurrences.last)}',
                                ),
                              ],
                            ),
                            style: context.text.bodySmall?.copyWith(color: p.accentText),
                          )
                        else
                          Text(
                            'Last payment on ${DateLabels.short(emiOccurrences.last)}',
                            style: context.text.bodySmall?.copyWith(color: p.accentText),
                          ),
                      ],
                    ),
                  ),
                  CircleIconButton(
                    icon: Icons.remove_rounded,
                    size: 32,
                    iconSize: 16,
                    onPressed: emiOccurrences.length > 1
                        ? () => _setInstallmentCount(emiOccurrences.length - 1)
                        : null,
                  ),
                  const Gap(4),
                  CircleIconButton(
                    icon: Icons.add_rounded,
                    size: 32,
                    iconSize: 16,
                    onPressed: emiOccurrences.length < 360
                        ? () => _setInstallmentCount(emiOccurrences.length + 1)
                        : null,
                  ),
                ],
              ),
            ),
          ],
          if (preview.isNotEmpty) ...[
            const Gap(Insets.md),
            Text(
              'Upcoming: ${preview.map(DateLabels.short).join('  ·  ')}',
              style: context.text.bodySmall?.copyWith(color: p.ink2),
            ),
          ],
          const Gap(Insets.xl),
          AppCard(
            padding: const EdgeInsets.fromLTRB(Insets.lg, 6, Insets.sm, 6),
            child: Column(
              children: [
                _SwitchRow(
                  title: 'Record automatically',
                  subtitle: _autoPost
                      ? 'Added to your history on each due date.'
                      : 'You\'ll confirm each payment from Plan → Bills.',
                  value: _autoPost,
                  onChanged: (v) => setState(() => _autoPost = v),
                ),
                if (_editing) ...[
                  Divider(color: p.hairline, height: 1),
                  _SwitchRow(
                    title: 'Active',
                    subtitle: _active
                        ? 'Running on schedule.'
                        : 'Paused. Nothing will be recorded.',
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, Insets.md),
          child: AppButton(
            label: _editing ? 'Save changes' : 'Save',
            loading: _saving,
            onPressed: _save,
          ),
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, style: context.text.bodyMedium?.copyWith(color: context.palette.ink2)),
      const Gap(2),
      Icon(Icons.chevron_right_rounded, size: 20, color: context.palette.ink3),
    ],
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              const Gap(2),
              Text(subtitle, style: context.text.bodySmall),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: (v) {
            Haptics.selection();
            onChanged(v);
          },
        ),
      ],
    ),
  );
}
