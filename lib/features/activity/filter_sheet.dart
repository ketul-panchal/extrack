import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_icons.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/sheets.dart';

Future<TxnFilter?> showFilterSheet(BuildContext context, TxnFilter filter) =>
    showAppSheet<TxnFilter>(context, builder: (_) => _FilterSheet(initial: filter));

enum DatePreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3Months('Last 3 months'),
  thisYear('This year'),
  custom('Custom…');

  const DatePreset(this.label);
  final String label;
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final TxnFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TxnFilter _f = widget.initial;
  late final _min = TextEditingController(
    text: widget.initial.minAmount == null
        ? ''
        : ref.read(moneyFormatProvider).toInput(widget.initial.minAmount!),
  );
  late final _max = TextEditingController(
    text: widget.initial.maxAmount == null
        ? ''
        : ref.read(moneyFormatProvider).toInput(widget.initial.maxAmount!),
  );

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Set<T> _toggle<T>(Set<T> set, T v) => set.contains(v) ? ({...set}..remove(v)) : {...set, v};

  Future<void> _applyPreset(DatePreset preset) async {
    final calc = ref.read(periodCalculatorProvider);
    final now = DateTime.now();
    final month = calc.month(now);
    switch (preset) {
      case DatePreset.thisMonth:
        setState(() => _f = _f.copyWith(from: () => month.start, to: () => month.end));
      case DatePreset.lastMonth:
        final last = calc.previous(month);
        setState(() => _f = _f.copyWith(from: () => last.start, to: () => last.end));
      case DatePreset.last3Months:
        setState(
          () => _f = _f.copyWith(from: () => calc.shift(month, -2).start, to: () => month.end),
        );
      case DatePreset.thisYear:
        final y = calc.year(now);
        setState(() => _f = _f.copyWith(from: () => y.start, to: () => y.end));
      case DatePreset.custom:
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(now.year + 2, 12, 31),
          initialDateRange: _f.from != null && _f.to != null
              ? DateTimeRange(start: _f.from!, end: _f.to!.subtract(const Duration(days: 1)))
              : null,
        );
        if (range == null || !mounted) return;
        setState(
          () => _f = _f.copyWith(
            from: () => dateOnly(range.start),
            to: () => DateTime(range.end.year, range.end.month, range.end.day + 1),
          ),
        );
    }
  }

  DatePreset? _activePreset() {
    if (_f.from == null && _f.to == null) return null;
    final calc = ref.read(periodCalculatorProvider);
    final now = DateTime.now();
    final month = calc.month(now);
    final last = calc.previous(month);
    final y = calc.year(now);
    if (_f.from == month.start && _f.to == month.end) return DatePreset.thisMonth;
    if (_f.from == last.start && _f.to == last.end) return DatePreset.lastMonth;
    if (_f.from == calc.shift(month, -2).start && _f.to == month.end) return DatePreset.last3Months;
    if (_f.from == y.start && _f.to == y.end) return DatePreset.thisYear;
    return DatePreset.custom;
  }

  void _apply() {
    final money = ref.read(moneyFormatProvider);
    final min = money.parse(_min.text);
    final max = money.parse(_max.text);
    Navigator.pop(context, _f.copyWith(minAmount: () => min, maxAmount: () => max));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final money = ref.watch(moneyFormatProvider);
    final preset = _activePreset();

    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, Insets.xl, Insets.page, Insets.sm),
      child: Text(text, style: context.text.labelMedium?.copyWith(color: p.ink3)),
    );
    Widget wrap(List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.page),
      child: Wrap(spacing: 8, runSpacing: 8, children: children),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: 'Filters',
          trailing: AppButton.ghost(
            label: 'Reset',
            onPressed: () {
              _min.clear();
              _max.clear();
              setState(() => _f = _f.clearFilters());
            },
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              label('Type'),
              wrap([
                for (final k in TxnKind.values)
                  SelectChip(
                    label: k.label,
                    dense: true,
                    selected: _f.kinds.contains(k),
                    onTap: () => setState(() => _f = _f.copyWith(kinds: _toggle(_f.kinds, k))),
                  ),
              ]),
              label('Date'),
              wrap([
                SelectChip(
                  label: 'Any time',
                  dense: true,
                  selected: preset == null,
                  onTap: () => setState(() => _f = _f.copyWith(from: () => null, to: () => null)),
                ),
                for (final d in DatePreset.values)
                  SelectChip(
                    label: d == DatePreset.custom && preset == DatePreset.custom
                        ? rangeLabel(_f.from!, _f.to!.subtract(const Duration(days: 1)))
                        : d.label,
                    dense: true,
                    selected: preset == d,
                    onTap: () => _applyPreset(d),
                  ),
              ]),
              label('Categories'),
              wrap([
                for (final c in categories.where((c) => !c.archived))
                  SelectChip(
                    label: c.name,
                    dense: true,
                    leading: Icon(
                      AppIcons.of(c.icon),
                      size: 16,
                      color: _f.categoryIds.contains(c.id) ? p.onPrimary : p.entity(c.color),
                    ),
                    selected: _f.categoryIds.contains(c.id),
                    onTap: () => setState(
                      () => _f = _f.copyWith(categoryIds: _toggle(_f.categoryIds, c.id)),
                    ),
                  ),
              ]),
              label('Accounts'),
              wrap([
                for (final a in accounts)
                  SelectChip(
                    label: a.name,
                    dense: true,
                    selected: _f.accountIds.contains(a.id),
                    onTap: () =>
                        setState(() => _f = _f.copyWith(accountIds: _toggle(_f.accountIds, a.id))),
                  ),
              ]),
              label('Amount'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.page),
                child: Row(
                  children: [
                    Expanded(
                      child: _AmountField(
                        controller: _min,
                        hint: 'Min',
                        symbol: money.currency.symbol,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
                      child: Text('–', style: context.text.titleMedium?.copyWith(color: p.ink3)),
                    ),
                    Expanded(
                      child: _AmountField(
                        controller: _max,
                        hint: 'Max',
                        symbol: money.currency.symbol,
                      ),
                    ),
                  ],
                ),
              ),
              label('Sort by'),
              wrap([
                for (final s in TxnSort.values)
                  SelectChip(
                    label: s.label,
                    dense: true,
                    selected: _f.sort == s,
                    onTap: () => setState(() => _f = _f.copyWith(sort: s)),
                  ),
              ]),
              const Gap(Insets.xl),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, Insets.lg),
          child: AppButton(label: 'Show results', onPressed: _apply),
        ),
      ],
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.hint, required this.symbol});

  final TextEditingController controller;
  final String hint;
  final String symbol;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    style: context.text.titleSmall,
    decoration: InputDecoration(hintText: hint, prefixText: '$symbol '),
  );
}
