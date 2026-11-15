import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/pickers.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/sheets.dart';

/// Create or edit an account. Resolves to the account id on save.
Future<int?> showAccountEditor(BuildContext context, {Account? account}) =>
    showAppSheet<int>(context, builder: (_) => _AccountEditor(account: account));

class _AccountEditor extends ConsumerStatefulWidget {
  const _AccountEditor({required this.account});

  final Account? account;

  @override
  ConsumerState<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends ConsumerState<_AccountEditor> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late AccountType _type = widget.account?.type ?? AccountType.bank;
  late String _icon = widget.account?.icon ?? _type.defaultIcon;
  late int _color = widget.account?.color ?? defaultAccountColor(_type);
  late bool _iconTouched = widget.account != null;
  late bool _include = widget.account?.includeInTotal ?? true;
  late bool _negative = (widget.account?.openingBalance ?? 0) < 0;
  late final _balance = TextEditingController(
    text: widget.account == null || widget.account!.openingBalance == 0
        ? ''
        : ref.read(moneyFormatProvider).toInput(widget.account!.openingBalance.abs()),
  );
  late bool _isDefault =
      widget.account != null && ref.read(settingsProvider).defaultAccountId == widget.account!.id;

  bool get _editing => widget.account != null;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _setType(AccountType t) {
    setState(() {
      final wasDefaultColor = _color == defaultAccountColor(_type);
      _type = t;
      if (!_iconTouched) _icon = t.defaultIcon;
      if (wasDefaultColor && !_editing) _color = defaultAccountColor(t);
      if (!_editing && _balance.text.isEmpty) _negative = t.isLiability;
    });
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
    if (key != null) {
      setState(() {
        _icon = key;
        _iconTouched = true;
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      Haptics.error();
      return;
    }
    final amount = ref.read(moneyFormatProvider).parse(_balance.text) ?? 0;
    final opening = _negative ? -amount : amount;
    final repo = ref.read(accountRepositoryProvider);
    int id;
    if (_editing) {
      await repo.save(
        widget.account!.copyWith(
          name: name,
          type: _type,
          icon: _icon,
          color: _color,
          openingBalance: opening,
          includeInTotal: _include,
        ),
      );
      id = widget.account!.id;
    } else {
      id = await repo.add(
        name: name,
        type: _type,
        icon: _icon,
        color: _color,
        openingBalance: opening,
        includeInTotal: _include,
      );
    }
    final settings = ref.read(settingsProvider.notifier);
    final currentDefault = ref.read(settingsProvider).defaultAccountId;
    if (_isDefault && currentDefault != id) {
      await settings.update((s) => s.copyWith(defaultAccountId: () => id));
    } else if (!_isDefault && currentDefault == id) {
      await settings.update((s) => s.copyWith(defaultAccountId: () => null));
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
          Text(_editing ? 'Edit account' : 'New account', style: context.text.headlineSmall),
          const Gap(Insets.lg),
          Row(
            children: [
              Pressable(
                onTap: _pickIcon,
                child: EntityIcon(icon: _icon, color: _color, size: 56),
              ),
              const Gap(Insets.lg),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: !_editing,
                  maxLength: 48,
                  textCapitalization: TextCapitalization.words,
                  style: context.text.titleMedium,
                  decoration: const InputDecoration(hintText: 'e.g. HDFC Savings', counterText: ''),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const Gap(Insets.lg),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in AccountType.values)
                SelectChip(
                  label: t.label,
                  dense: true,
                  selected: _type == t,
                  onTap: () => _setType(t),
                ),
            ],
          ),
          const Gap(Insets.xl),
          Text(
            _type.isLiability ? 'Amount owed right now' : 'Balance right now',
            style: context.text.labelMedium?.copyWith(color: p.ink3),
          ),
          const Gap(Insets.sm),
          Row(
            children: [
              Pressable(
                onTap: () => setState(() => _negative = !_negative),
                semanticLabel: 'Toggle negative balance',
                child: AnimatedContainer(
                  duration: Motion.medium,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _negative ? p.negativeFill.withValues(alpha: 0.14) : p.surface2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _negative ? '−' : '+',
                    style: context.text.headlineSmall?.copyWith(
                      color: _negative ? p.negative : p.ink2,
                    ),
                  ),
                ),
              ),
              const Gap(Insets.sm),
              Expanded(
                child: TextField(
                  controller: _balance,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  style: context.text.titleLarge?.tabular,
                  decoration: InputDecoration(
                    hintText: '0',
                    prefixText: money.style.symbolFirst ? '${money.currency.symbol} ' : null,
                    suffixText: money.style.symbolFirst ? null : money.currency.symbol,
                  ),
                ),
              ),
            ],
          ),
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This is the starting balance before any transactions. To match your bank, use "Update balance" on the account.',
                style: context.text.bodySmall?.copyWith(color: p.ink3),
              ),
            ),
          const Gap(Insets.xl),
          Text('Color', style: context.text.labelMedium?.copyWith(color: p.ink3)),
          const Gap(Insets.sm),
          ColorSwatchPicker(selected: _color, onChanged: (c) => setState(() => _color = c)),
          const Gap(Insets.lg),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Count in total balance', style: context.text.titleSmall),
            subtitle: Text(
              'Turn off for accounts you only want to track.',
              style: context.text.bodySmall,
            ),
            value: _include,
            onChanged: (v) => setState(() => _include = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Default account', style: context.text.titleSmall),
            subtitle: Text(
              'Pre-selected when you add a transaction.',
              style: context.text.bodySmall,
            ),
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
          const Gap(Insets.lg),
          AppButton(
            label: _editing ? 'Save' : 'Create account',
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}
