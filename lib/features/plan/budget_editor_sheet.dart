import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/pickers/picker_sheets.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/sheets.dart';

/// Sets or removes a monthly limit. [categoryId] null means the overall
/// budget; pass [pickCategory] to let the user choose a category first.
Future<void> showBudgetEditor(
  BuildContext context, {
  int? categoryId,
  bool pickCategoryFirst = false,
}) async {
  var id = categoryId;
  if (pickCategoryFirst) {
    id = await pickCategory(context, kind: CategoryKind.expense);
    if (id == null || !context.mounted) return;
  }
  await showAppSheet<void>(context, builder: (_) => _BudgetEditor(categoryId: id));
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({required this.categoryId});

  final int? categoryId;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  late final TextEditingController _amount;
  Budget? _existing;
  int? _suggested;

  @override
  void initState() {
    super.initState();
    final money = ref.read(moneyFormatProvider);
    _existing = (ref.read(budgetsProvider).value ?? const <Budget>[])
        .where((b) => b.categoryId == widget.categoryId)
        .firstOrNull;
    _amount = TextEditingController(
      text: _existing == null ? '' : money.toInput(_existing!.amount),
    );
    _loadSuggestion();
  }

  /// Average monthly spending over the last three full cycles, rounded up.
  Future<void> _loadSuggestion() async {
    final calc = ref.read(periodCalculatorProvider);
    final current = calc.month(DateTime.now());
    final start = calc.shift(current, -3).start;
    final txns = await ref.read(txnRepositoryProvider).inRange(start, current.start);
    final spent = txns
        .where(
          (t) =>
              t.kind == TxnKind.expense &&
              (widget.categoryId == null || t.categoryId == widget.categoryId),
        )
        .fold<int>(0, (s, t) => s + t.amount);
    if (spent <= 0 || !mounted) return;
    final unit = ref.read(moneyFormatProvider).unit;
    final avg = spent / 3;
    // Round to a friendly number: nearest 10, 100 or 1000 units.
    final step = avg / unit >= 10000 ? 1000 : (avg / unit >= 1000 ? 100 : 10);
    setState(() => _suggested = ((avg / unit / step).ceil() * step * unit).round());
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final money = ref.read(moneyFormatProvider);
    final value = money.parse(_amount.text);
    if (value == null || value <= 0) {
      Haptics.error();
      return;
    }
    await ref.read(budgetRepositoryProvider).set(widget.categoryId, value);
    Haptics.success();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    await ref.read(budgetRepositoryProvider).set(widget.categoryId, null);
    Haptics.medium();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final money = ref.watch(moneyFormatProvider);
    final category = widget.categoryId == null
        ? null
        : ref.watch(categoryMapProvider)[widget.categoryId];
    final title = category == null ? 'Monthly budget' : category.name;
    final calc = ref.watch(periodCalculatorProvider);
    final resets = calc.monthStartDay == 1
        ? 'Resets on the 1st of each month.'
        : 'Resets on day ${calc.monthStartDay} of each month.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (category != null) ...[
                EntityIcon(icon: category.icon, color: category.color, size: 44),
                const Gap(Insets.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.headlineSmall),
                    Text(
                      category == null
                          ? 'A limit for all spending. $resets'
                          : 'Monthly limit. $resets',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(Insets.xl),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: context.text.headlineMedium?.tabular,
            decoration: InputDecoration(
              hintText: '0',
              prefixIcon: money.style.symbolFirst
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16, right: 6),
                      child: Text(
                        money.currency.symbol,
                        style: context.text.headlineSmall?.copyWith(color: p.ink3),
                      ),
                    )
                  : null,
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixText: money.style.symbolFirst ? null : money.currency.symbol,
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_suggested != null) ...[
            const Gap(Insets.md),
            Pressable(
              onTap: () => setState(() => _amount.text = money.toInput(_suggested!)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: p.accentText),
                    const Gap(Insets.sm),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Suggested: '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: MoneyText(
                                _suggested!,
                                reveal: true,
                                style: context.text.labelLarge,
                                color: p.accentText,
                              ),
                            ),
                            const TextSpan(text: ' · your 3-month average'),
                          ],
                        ),
                        style: context.text.labelMedium?.copyWith(color: p.accentText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Gap(Insets.xl),
          Row(
            children: [
              if (_existing != null) ...[
                Expanded(
                  child: AppButton(
                    label: 'Remove',
                    variant: ButtonVariant.secondary,
                    onPressed: _remove,
                  ),
                ),
                const Gap(Insets.md),
              ],
              Expanded(
                flex: 2,
                child: AppButton(label: 'Save budget', onPressed: _save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
