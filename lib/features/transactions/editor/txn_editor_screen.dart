import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/amount_input.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_icons.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/date_labels.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/core/time/recurrence.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/pickers/picker_sheets.dart';
import 'package:spent/features/transactions/editor/keypad.dart';
import 'package:spent/features/transactions/txn_actions.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/segmented.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';

class TxnEditorScreen extends ConsumerStatefulWidget {
  const TxnEditorScreen({
    super.key,
    this.txnId,
    this.initialKind = TxnKind.expense,
    this.initialCategoryId,
    this.initialAccountId,
  });

  final int? txnId;
  final TxnKind initialKind;
  final int? initialCategoryId;
  final int? initialAccountId;

  @override
  ConsumerState<TxnEditorScreen> createState() => _TxnEditorScreenState();
}

class _TxnEditorScreenState extends ConsumerState<TxnEditorScreen> {
  late final MoneyFormat _money = ref.read(moneyFormatProvider);
  late AmountInput _input = AmountInput.empty(_money.decimals);
  late TxnKind _kind = widget.initialKind;
  late int? _categoryId = widget.initialCategoryId;
  late int? _accountId = widget.initialAccountId ?? ref.read(settingsProvider).defaultAccountId;
  int? _toAccountId;
  DateTime _date = DateTime.now();
  Frequency? _repeat;
  Txn? _original;
  int? _pinnedCategory;

  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  Timer? _debounce;
  List<NoteSuggestion> _suggestions = const [];
  Map<int, int> _usage = const {};

  int _amountShake = 0;
  int _categoryShake = 0;
  bool _saving = false;

  bool get _editing => widget.txnId != null;

  @override
  void initState() {
    super.initState();
    _note.addListener(_onNoteChanged);
    _noteFocus.addListener(() => setState(() {}));
    if (_editing) unawaited(_load());
    unawaited(_loadUsage());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final t = await ref.read(txnRepositoryProvider).byId(widget.txnId!);
    if (!mounted) return;
    if (t == null) {
      context.pop();
      return;
    }
    setState(() {
      _original = t;
      _kind = t.kind;
      _input = AmountInput.fromMinor(t.amount, _money);
      _categoryId = t.categoryId;
      _accountId = t.accountId;
      _toAccountId = t.toAccountId;
      _date = t.date;
      _pinnedCategory = t.categoryId;
    });
    _note.text = t.note;
    await _loadUsage();
  }

  Future<void> _loadUsage() async {
    if (_kind == TxnKind.transfer) return;
    final usage = await ref.read(txnRepositoryProvider).categoryUsage(_kind);
    if (mounted) setState(() => _usage = usage);
  }

  void _onNoteChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), () async {
      if (_kind == TxnKind.transfer) return;
      final text = _note.text;
      final list = await ref.read(txnRepositoryProvider).suggestions(_kind, text);
      if (!mounted) return;
      setState(() {
        _suggestions = list
            .where((s) => s.note.toLowerCase() != text.trim().toLowerCase())
            .toList();
      });
    });
  }

  bool get _dirty {
    final o = _original;
    if (o == null) return !_input.isEmpty || _note.text.trim().isNotEmpty;
    return _input.evaluate(_money.unit) != o.amount ||
        _kind != o.kind ||
        _categoryId != o.categoryId ||
        _accountId != o.accountId ||
        _toAccountId != o.toAccountId ||
        _date != o.date ||
        _note.text.trim() != o.note;
  }

  // ── Input ────────────────────────────────────────────────────────────────

  void _onKey(KeypadKey key) {
    setState(() {
      _input = switch (key) {
        DigitKey(digit: -1) => _input.doubleZero(),
        DigitKey(:final digit) => _input.digit(digit),
        DotKey() => _input.dot(),
        BackspaceKey() => _input.backspace(),
        ClearKey() => _input.clear(),
        OpKey(:final op) => _input.operator(op),
      };
    });
  }

  KeyEventResult _onHardwareKey(FocusNode node, KeyEvent event) {
    if (_noteFocus.hasFocus) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      unawaited(_save());
      return KeyEventResult.handled;
    }
    final key = keypadKeyFor(event);
    if (key == null) return KeyEventResult.ignored;
    _onKey(key);
    return KeyEventResult.handled;
  }

  void _setKind(TxnKind kind) {
    if (kind == _kind) return;
    setState(() {
      final wasTransfer = _kind == TxnKind.transfer;
      _kind = kind;
      if (_original?.kind != kind || kind == TxnKind.transfer || wasTransfer) {
        _categoryId = null;
        _pinnedCategory = null;
      }
      _suggestions = const [];
      _usage = const {};
    });
    unawaited(_loadUsage());
  }

  void _applySuggestion(NoteSuggestion s) {
    Haptics.selection();
    setState(() {
      _note.text = s.note;
      _note.selection = TextSelection.collapsed(offset: s.note.length);
      if (s.categoryId != null && ref.read(categoryMapProvider)[s.categoryId]?.archived == false) {
        _categoryId = s.categoryId;
        _pinnedCategory = s.categoryId;
      }
      if (_input.isEmpty) _input = AmountInput.fromMinor(s.lastAmount, _money);
      _suggestions = const [];
    });
    _noteFocus.unfocus();
  }

  // ── Pickers ──────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    _noteFocus.unfocus();
    final now = DateTime.now();
    final choice = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Date'),
          OptionRow(
            leading: const Icon(Icons.today_rounded),
            title: 'Today',
            subtitle: DateLabels.short(now),
            selected: dateOnly(_date) == dateOnly(now),
            onTap: () => Navigator.pop(ctx, 'today'),
          ),
          OptionRow(
            leading: const Icon(Icons.history_rounded),
            title: 'Yesterday',
            subtitle: DateLabels.short(now.subtract(const Duration(days: 1))),
            selected: daysBetween(_date, now) == 1,
            onTap: () => Navigator.pop(ctx, 'yesterday'),
          ),
          OptionRow(
            leading: const Icon(Icons.calendar_month_rounded),
            title: 'Pick a date…',
            onTap: () => Navigator.pop(ctx, 'pick'),
          ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    DateTime? day;
    if (choice == 'today') day = now;
    if (choice == 'yesterday') day = now.subtract(const Duration(days: 1));
    if (choice == 'pick') {
      day = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 2, 12, 31),
      );
    }
    if (day == null || !mounted) return;
    // Keep a time of day so transactions stay in the order they were added.
    final time = _editing ? _date : now;
    setState(
      () => _date = DateTime(day!.year, day.month, day.day, time.hour, time.minute, time.second),
    );
  }

  Future<void> _pickRepeat() async {
    _noteFocus.unfocus();
    DateTime next(Frequency f) => Recurrence(frequency: f, every: 1, anchor: _date).after(_date);
    final result = await showAppSheet<Object>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(
            title: 'Repeat',
            subtitle: 'Recurring transactions are added automatically when due.',
          ),
          OptionRow(
            title: 'Does not repeat',
            selected: _repeat == null,
            onTap: () => Navigator.pop(ctx, 'none'),
          ),
          for (final f in Frequency.values)
            OptionRow(
              title: f.label(1),
              subtitle: 'Next on ${DateLabels.short(next(f))}',
              selected: _repeat == f,
              onTap: () => Navigator.pop(ctx, f),
            ),
          const Gap(Insets.md),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _repeat = result is Frequency ? result : null);
  }

  Future<void> _pickCategory() async {
    _noteFocus.unfocus();
    final id = await pickCategory(
      context,
      kind: _kind == TxnKind.income ? CategoryKind.income : CategoryKind.expense,
      selected: _categoryId,
    );
    if (id != null && mounted) {
      setState(() {
        _categoryId = id;
        _pinnedCategory = id;
      });
    }
  }

  Future<void> _pickAccount({bool destination = false}) async {
    _noteFocus.unfocus();
    final id = await pickAccount(
      context,
      title: destination ? 'To account' : (_kind == TxnKind.transfer ? 'From account' : 'Account'),
      selected: destination ? _toAccountId : _accountId,
    );
    if (id == null || !mounted) return;
    setState(() {
      if (destination) {
        _toAccountId = id;
        if (_accountId == id) _accountId = null;
      } else {
        _accountId = id;
        if (_toAccountId == id) _toAccountId = null;
      }
    });
  }

  Future<void> _showMore() async {
    final t = _original;
    if (t == null) return;
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Transaction'),
          OptionRow(
            leading: const Icon(Icons.copy_rounded),
            title: 'Duplicate to today',
            onTap: () => Navigator.pop(ctx, 'duplicate'),
          ),
          if (t.recurringId != null)
            OptionRow(
              leading: const Icon(Icons.autorenew_rounded),
              title: 'View recurring rule',
              onTap: () => Navigator.pop(ctx, 'rule'),
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
    if (!mounted || action == null) return;
    switch (action) {
      case 'duplicate':
        await duplicateTxn(ref, t);
        if (!mounted) return;
        AppToast.show(context, 'Duplicated to today', icon: Icons.copy_rounded, aboveNavBar: true);
        context.pop();
      case 'rule':
        unawaited(context.push('/recurring/${t.recurringId}'));
      case 'delete':
        unawaited(deleteTxnWithUndo(context, ref, t));
        context.pop();
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    _noteFocus.unfocus();
    final amount = _input.evaluate(_money.unit);
    if (amount == null || amount <= 0) {
      Haptics.error();
      setState(() => _amountShake++);
      return;
    }
    final accounts = ref.read(activeAccountsProvider);
    final accountId = _accountId ?? (accounts.isEmpty ? null : accounts.first.id);
    if (accountId == null) {
      AppToast.show(context, 'Add an account first', icon: Icons.account_balance_wallet_outlined);
      return;
    }
    if (_kind == TxnKind.transfer) {
      if (_toAccountId == null || _toAccountId == accountId) {
        Haptics.error();
        setState(() => _categoryShake++);
        AppToast.show(context, 'Choose two different accounts', icon: Icons.swap_horiz_rounded);
        return;
      }
    } else if (_categoryId == null) {
      Haptics.error();
      setState(() => _categoryShake++);
      AppToast.show(context, 'Pick a category', icon: Icons.category_outlined);
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(txnRepositoryProvider);
    final note = _note.text.trim();
    final transfer = _kind == TxnKind.transfer;
    final original = _original;
    if (original != null) {
      await repo.save(
        original.copyWith(
          kind: _kind,
          amount: amount,
          accountId: accountId,
          categoryId: Value(transfer ? null : _categoryId),
          toAccountId: Value(transfer ? _toAccountId : null),
          date: _date,
          note: note,
        ),
      );
    } else {
      int? ruleId;
      if (_repeat != null) {
        ruleId = await ref
            .read(recurringRepositoryProvider)
            .add(
              kind: _kind,
              amount: amount,
              accountId: accountId,
              categoryId: _categoryId,
              toAccountId: _toAccountId,
              note: note,
              frequency: _repeat!,
              startDate: _date,
              nextDue: Recurrence(frequency: _repeat!, every: 1, anchor: _date).after(_date),
            );
      }
      await repo.add(
        kind: _kind,
        amount: amount,
        accountId: accountId,
        categoryId: _categoryId,
        toAccountId: _toAccountId,
        note: note,
        date: _date,
        recurringId: ruleId,
      );
    }
    Haptics.success();
    final alert = _kind == TxnKind.expense ? await _budgetAlert(amount, original) : null;
    if (!mounted) return;
    if (alert != null) {
      AppToast.show(
        context,
        alert.$1,
        icon: alert.$2 == ToastTone.danger
            ? Icons.error_outline_rounded
            : Icons.warning_amber_rounded,
        tone: alert.$2,
        aboveNavBar: true,
      );
    } else {
      AppToast.show(
        context,
        original != null ? 'Changes saved' : '${_kind.label} added',
        icon: Icons.check_circle_rounded,
        tone: ToastTone.success,
        aboveNavBar: true,
        duration: const Duration(milliseconds: 2200),
      );
    }
    context.pop();
  }

  /// A warning when this expense pushes a budget past 80% or 100%.
  Future<(String, ToastTone)?> _budgetAlert(int amount, Txn? original) async {
    final period = ref.read(periodCalculatorProvider).month(DateTime.now());
    if (!period.contains(_date)) return null;
    final budgets = ref.read(budgetsProvider).value ?? const <Budget>[];
    if (budgets.isEmpty) return null;
    final txns = await ref.read(txnRepositoryProvider).inRange(period.start, period.end);
    final expenses = txns.where((t) => t.kind == TxnKind.expense);
    final total = expenses.fold<int>(0, (s, t) => s + t.amount);
    final inCategory = expenses
        .where((t) => t.categoryId == _categoryId)
        .fold<int>(0, (s, t) => s + t.amount);
    // What this save added (an edit only adds the difference).
    final added =
        original != null && original.kind == TxnKind.expense && period.contains(original.date)
        ? amount - original.amount
        : amount;
    final categoryName = ref.read(categoryMapProvider)[_categoryId]?.name ?? 'Category';
    final checks = <(Budget?, int, String)>[
      (
        budgets.where((b) => b.categoryId == _categoryId).firstOrNull,
        inCategory,
        '$categoryName budget',
      ),
      (budgets.where((b) => b.categoryId == null).firstOrNull, total, 'Monthly budget'),
    ];
    for (final (budget, spent, name) in checks) {
      if (budget == null || budget.amount <= 0) continue;
      final now = spent / budget.amount;
      final before = (spent - added) / budget.amount;
      if (now > 1 && before <= 1) {
        return (
          'Over your ${name.replaceFirst(' budget', '')} budget by ${_money.format(spent - budget.amount)}',
          ToastTone.danger,
        );
      }
      if (now >= 0.8 && before < 0.8) {
        return ('$name: ${(now * 100).round()}% used', ToastTone.warning);
      }
    }
    return null;
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirmSheet(
      context,
      title: _editing ? 'Discard changes?' : 'Discard this ${_kind.label.toLowerCase()}?',
      message: 'What you entered will be lost.',
      confirmLabel: 'Discard',
      icon: Icons.edit_off_rounded,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final accounts = ref.watch(activeAccountsProvider);
    final accountMap = ref.watch(accountMapProvider);
    final accountId = _accountId ?? (accounts.isEmpty ? null : accounts.first.id);
    final account = accountMap[accountId];
    final height = MediaQuery.sizeOf(context).height;
    final keyHeight = height < 700 ? 48.0 : (height < 800 ? 54.0 : 58.0);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _original = null;
          _input = _input.clear();
          _note.clear();
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: p.bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Focus(
            autofocus: true,
            onKeyEvent: _onHardwareKey,
            child: Column(
              children: [
                _TopBar(
                  kind: _kind,
                  editing: _editing,
                  onKind: _setKind,
                  onClose: () async {
                    if (await _confirmDiscard() && context.mounted) {
                      _original = null;
                      _input = _input.clear();
                      _note.clear();
                      context.pop();
                    }
                  },
                  onMore: _showMore,
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _noteFocus.unfocus,
                    child: _AmountArea(
                      input: _input,
                      money: _money,
                      kind: _kind,
                      shake: _amountShake,
                      note: _note,
                      noteFocus: _noteFocus,
                      suggestions: _noteFocus.hasFocus ? _suggestions : const [],
                      onSuggestion: _applySuggestion,
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.of(context, Motion.medium),
                  curve: Motion.emphasized,
                  alignment: Alignment.topCenter,
                  child: keyboard
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Insets.page,
                            0,
                            Insets.page,
                            Insets.sm,
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: AppButton.ghost(label: 'Done', onPressed: _noteFocus.unfocus),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Shake(
                              trigger: _categoryShake,
                              child: _kind == TxnKind.transfer
                                  ? _TransferRow(
                                      from: account,
                                      to: accountMap[_toAccountId],
                                      onFrom: _pickAccount,
                                      onTo: () => _pickAccount(destination: true),
                                      onSwap: () => setState(() {
                                        Haptics.selection();
                                        final a = _accountId ?? accountId;
                                        _accountId = _toAccountId;
                                        _toAccountId = a;
                                      }),
                                    )
                                  : _CategoryStrip(
                                      kind: _kind == TxnKind.income
                                          ? CategoryKind.income
                                          : CategoryKind.expense,
                                      selected: _categoryId,
                                      pinned: _pinnedCategory,
                                      usage: _usage,
                                      onSelect: (id) => setState(() => _categoryId = id),
                                      onMore: _pickCategory,
                                    ),
                            ),
                            const Gap(Insets.md),
                            _MetaRow(
                              children: [
                                _MetaChip(
                                  icon: Icons.calendar_today_rounded,
                                  label: DateLabels.chip(_date),
                                  onTap: _pickDate,
                                ),
                                if (_kind != TxnKind.transfer)
                                  _MetaChip(
                                    leading: account == null
                                        ? null
                                        : EntityIcon(
                                            icon: account.icon,
                                            color: account.color,
                                            size: 22,
                                          ),
                                    icon: account == null
                                        ? Icons.account_balance_wallet_outlined
                                        : null,
                                    label: account?.name ?? 'Account',
                                    onTap: _pickAccount,
                                  ),
                                if (!_editing)
                                  _MetaChip(
                                    icon: Icons.autorenew_rounded,
                                    label: _repeat?.label(1) ?? 'Repeat',
                                    active: _repeat != null,
                                    onTap: _pickRepeat,
                                  ),
                              ],
                            ),
                            const Gap(Insets.md),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
                              child: AmountKeypad(
                                onKey: _onKey,
                                keyHeight: keyHeight,
                                decimalSeparator: _money.style.decimalSeparator,
                                allowDecimal: _money.decimals > 0,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Insets.md,
                                0,
                                Insets.md,
                                Insets.sm,
                              ),
                              child: AppButton(
                                label: _editing
                                    ? 'Save changes'
                                    : 'Add ${_kind.label.toLowerCase()}',
                                icon: Icons.check_rounded,
                                loading: _saving,
                                height: keyHeight + 2,
                                onPressed: _save,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.kind,
    required this.editing,
    required this.onKind,
    required this.onClose,
    required this.onMore,
  });

  final TxnKind kind;
  final bool editing;
  final ValueChanged<TxnKind> onKind;
  final VoidCallback onClose;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, 0),
    child: Row(
      children: [
        CircleIconButton(icon: Icons.close_rounded, tooltip: 'Close', onPressed: onClose),
        const Gap(Insets.md),
        Expanded(
          child: SegmentedTabs<TxnKind>(
            values: TxnKind.values,
            selected: kind,
            labelOf: (k) => k.label,
            onChanged: onKind,
          ),
        ),
        const Gap(Insets.md),
        if (editing)
          CircleIconButton(icon: Icons.more_horiz_rounded, tooltip: 'More', onPressed: onMore)
        else
          const SizedBox(width: 44),
      ],
    ),
  );
}

class _AmountArea extends StatelessWidget {
  const _AmountArea({
    required this.input,
    required this.money,
    required this.kind,
    required this.shake,
    required this.note,
    required this.noteFocus,
    required this.suggestions,
    required this.onSuggestion,
  });

  final AmountInput input;
  final MoneyFormat money;
  final TxnKind kind;
  final int shake;
  final TextEditingController note;
  final FocusNode noteFocus;
  final List<NoteSuggestion> suggestions;
  final ValueChanged<NoteSuggestion> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final empty = input.isEmpty;
    final color = empty ? p.ink3 : (kind == TxnKind.income ? p.positive : p.ink);
    final big = context.text.displayLarge!.copyWith(color: color, fontSize: 56, letterSpacing: -2);
    final symbol = context.text.displaySmall!.copyWith(color: p.ink3, fontWeight: FontWeight.w600);
    final result = input.hasOperator ? input.evaluate(money.unit) : null;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Shake(
                trigger: shake,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.xxl),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (money.style.symbolFirst) ...[
                          Text(money.currency.symbol, style: symbol),
                          const Gap(4),
                        ],
                        RollingText(input.display(money), style: big),
                        if (!money.style.symbolFirst) ...[
                          const Gap(6),
                          Text(money.currency.symbol, style: symbol),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.fast),
                child: input.hasOperator
                    ? Padding(
                        key: const ValueKey('result'),
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          result == null ? '= —' : '= ${money.format(result)}',
                          style: context.text.titleMedium?.copyWith(color: p.ink2).tabular,
                        ),
                      )
                    : const SizedBox(key: ValueKey('none'), height: 26),
              ),
              const Gap(Insets.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.xxxl),
                child: TextField(
                  controller: note,
                  focusNode: noteFocus,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  style: context.text.titleMedium,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: kind == TxnKind.transfer ? 'Add a note' : 'What was it for?',
                    counterText: '',
                    filled: true,
                    fillColor: noteFocus.hasFocus ? p.surface : p.surface2.withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ),
              AnimatedSize(
                duration: Motion.of(context, Motion.medium),
                curve: Motion.emphasized,
                child: suggestions.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: Insets.md),
                        child: SizedBox(
                          height: 38,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: Insets.page),
                            itemCount: suggestions.length,
                            separatorBuilder: (_, _) => const Gap(Insets.sm),
                            itemBuilder: (context, i) => _SuggestionChip(
                              suggestion: suggestions[i],
                              money: money,
                              onTap: () => onSuggestion(suggestions[i]),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends ConsumerWidget {
  const _SuggestionChip({required this.suggestion, required this.money, required this.onTap});

  final NoteSuggestion suggestion;
  final MoneyFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final category = ref.watch(categoryMapProvider)[suggestion.categoryId];
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category != null) ...[
              Icon(AppIcons.of(category.icon), size: 16, color: p.entity(category.color)),
              const Gap(6),
            ],
            Text(suggestion.note, style: context.text.labelLarge),
            const Gap(6),
            Text(
              money.format(suggestion.lastAmount),
              style: context.text.labelMedium?.copyWith(color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryStrip extends ConsumerWidget {
  const _CategoryStrip({
    required this.kind,
    required this.selected,
    required this.pinned,
    required this.usage,
    required this.onSelect,
    required this.onMore,
  });

  final CategoryKind kind;
  final int? selected;
  final int? pinned;
  final Map<int, int> usage;
  final ValueChanged<int> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final all = ref.watch(categoriesOfKindProvider(kind));
    // Most used first, keeping the user's order for ties; a category picked
    // from the full sheet jumps to the front so it's visible.
    final order = {for (var i = 0; i < all.length; i++) all[i].id: i};
    final sorted = [...all]
      ..sort((a, b) {
        if (a.id == pinned) return -1;
        if (b.id == pinned) return 1;
        final u = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
        return u != 0 ? u : order[a.id]!.compareTo(order[b.id]!);
      });
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.md),
        itemCount: sorted.length + 1,
        separatorBuilder: (_, _) => const Gap(Insets.sm),
        itemBuilder: (context, i) {
          if (i == sorted.length) {
            return Pressable(
              onTap: onMore,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Row(
                  children: [
                    Icon(Icons.grid_view_rounded, size: 17, color: p.ink2),
                    const Gap(6),
                    Text('All', style: context.text.labelLarge?.copyWith(color: p.ink2)),
                  ],
                ),
              ),
            );
          }
          final c = sorted[i];
          final isSelected = c.id == selected;
          final color = p.entity(c.color);
          return Pressable(
            pressedScale: 0.94,
            onTap: () => onSelect(c.id),
            child: AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.standard,
              padding: const EdgeInsets.only(left: 6, right: 14),
              decoration: BoxDecoration(
                color: isSelected ? color : (p.isDark ? p.surface2 : p.surface),
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: isSelected ? color : p.hairline),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: Motion.medium,
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.22)
                          : p.entitySoft(c.color),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.of(c.icon),
                      size: 17,
                      color: isSelected ? Colors.white : color,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    c.name,
                    style: context.text.labelLarge?.copyWith(
                      color: isSelected ? Colors.white : p.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.from,
    required this.to,
    required this.onFrom,
    required this.onTo,
    required this.onSwap,
  });

  final Account? from;
  final Account? to;
  final VoidCallback onFrom;
  final VoidCallback onTo;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Insets.md),
    child: Row(
      children: [
        Expanded(
          child: _AccountBox(label: 'From', account: from, onTap: onFrom),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
          child: CircleIconButton(
            icon: Icons.swap_horiz_rounded,
            size: 40,
            tooltip: 'Swap',
            onPressed: onSwap,
          ),
        ),
        Expanded(
          child: _AccountBox(label: 'To', account: to, onTap: onTo),
        ),
      ],
    ),
  );
}

class _AccountBox extends StatelessWidget {
  const _AccountBox({required this.label, required this.account, required this.onTap});

  final String label;
  final Account? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: p.isDark ? p.surface2 : p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            if (account != null)
              EntityIcon(icon: account!.icon, color: account!.color, size: 30)
            else
              Icon(Icons.add_circle_outline_rounded, color: p.ink3),
            const Gap(8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.labelSmall),
                  Text(
                    account?.name ?? 'Choose',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(
                      color: account == null ? p.ink3 : p.ink,
                    ),
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      itemCount: children.length,
      separatorBuilder: (_, _) => const Gap(Insets.sm),
      itemBuilder: (_, i) => children[i],
    ),
  );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.medium,
        padding: EdgeInsets.only(left: leading != null ? 8 : 12, right: 14),
        decoration: BoxDecoration(
          color: active ? p.accentSoft : p.surface2,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null)
              leading!
            else
              Icon(icon, size: 16, color: active ? p.accentText : p.ink2),
            const Gap(7),
            Text(
              label,
              style: context.text.labelLarge?.copyWith(color: active ? p.accentText : p.ink),
            ),
          ],
        ),
      ),
    );
  }
}
