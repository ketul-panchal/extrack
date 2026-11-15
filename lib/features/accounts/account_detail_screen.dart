import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/accounts/account_editor_sheet.dart';
import 'package:spent/features/transactions/txn_actions.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';
import 'package:spent/shared/widgets/txn_tile.dart';

class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final int accountId;

  Future<void> _updateBalance(BuildContext context, WidgetRef ref, Account a, int current) async {
    final money = ref.read(moneyFormatProvider);
    final controller = TextEditingController(text: money.toInput(current.abs()));
    var negative = current < 0;
    final result = await showAppSheet<int>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final p = ctx.palette;
          return Padding(
            padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Update balance', style: ctx.text.headlineSmall),
                const Gap(4),
                Text(
                  'Enter what ${a.name} shows right now. Your history stays as it is; the difference is applied to the starting balance.',
                  style: ctx.text.bodySmall,
                ),
                const Gap(Insets.lg),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => setSheet(() => negative = !negative),
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: negative ? p.negativeFill.withValues(alpha: 0.14) : p.surface2,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          negative ? '−' : '+',
                          style: ctx.text.headlineSmall?.copyWith(
                            color: negative ? p.negative : p.ink2,
                          ),
                        ),
                      ),
                    ),
                    const Gap(Insets.sm),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        style: ctx.text.headlineSmall?.tabular,
                        decoration: InputDecoration(
                          prefixText: money.style.symbolFirst ? '${money.currency.symbol} ' : null,
                          suffixText: money.style.symbolFirst ? null : money.currency.symbol,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(Insets.xl),
                AppButton(
                  label: 'Update',
                  onPressed: () {
                    final v = money.parse(controller.text);
                    if (v == null) return;
                    Navigator.pop(ctx, negative ? -v : v);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (result == null || result == current) return;
    await ref
        .read(accountRepositoryProvider)
        .save(a.copyWith(openingBalance: a.openingBalance + (result - current)));
    Haptics.success();
    if (context.mounted) {
      AppToast.show(
        context,
        'Balance updated',
        icon: Icons.check_circle_rounded,
        tone: ToastTone.success,
      );
    }
  }

  Future<void> _more(BuildContext context, WidgetRef ref, Account a) async {
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: a.name),
          OptionRow(
            leading: const Icon(Icons.edit_outlined),
            title: 'Edit',
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          OptionRow(
            leading: Icon(a.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: a.archived ? 'Restore' : 'Archive',
            subtitle: a.archived ? null : 'Hide it; keep its history and balance',
            onTap: () => Navigator.pop(ctx, 'archive'),
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
    if (action == null || !context.mounted) return;
    final repo = ref.read(accountRepositoryProvider);
    switch (action) {
      case 'edit':
        await showAccountEditor(context, account: a);
      case 'archive':
        await repo.setArchived(a.id, !a.archived);
      case 'delete':
        final count = await ref.read(txnRepositoryProvider).countForAccount(a.id);
        if (!context.mounted) return;
        final ok = await confirmSheet(
          context,
          title: 'Delete ${a.name}?',
          message: count == 0
              ? 'This account has no transactions.'
              : 'Its $count transaction${count == 1 ? '' : 's'} and recurring payments will be deleted too. Archive it instead to keep the history.',
        );
        if (!ok || !context.mounted) return;
        if (ref.read(settingsProvider).defaultAccountId == a.id) {
          await ref
              .read(settingsProvider.notifier)
              .update((s) => s.copyWith(defaultAccountId: () => null));
        }
        if (context.mounted) context.pop();
        await repo.delete(a.id);
        Haptics.medium();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final account = ref.watch(accountMapProvider)[accountId];
    if (account == null) return Scaffold(appBar: AppBar());
    final balance = ref.watch(balancesProvider).value?[accountId] ?? account.openingBalance;
    final txns = ref.watch(accountTxnsProvider(accountId)).value;
    final hidden = ref.watch(pendingDeletionsProvider);
    final views = txns == null
        ? null
        : TxnView.build(txns, ref.watch(categoryMapProvider), ref.watch(accountMapProvider));
    final month = ref.watch(currentMonthProvider);
    var inflow = 0;
    var outflow = 0;
    for (final t in txns ?? const <Txn>[]) {
      if (!month.contains(t.date)) continue;
      final incoming =
          t.kind == TxnKind.income || (t.kind == TxnKind.transfer && t.toAccountId == accountId);
      if (incoming) {
        inflow += t.amount;
      } else {
        outflow += t.amount;
      }
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'Options',
            onPressed: () => _more(context, ref, account),
          ),
          const Gap(Insets.sm),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      EntityIcon(icon: account.icon, color: account.color, size: 48),
                      const Gap(Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(account.name, style: context.text.titleLarge),
                            Text(account.type.label, style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(Insets.xl),
                  Text(
                    account.type.isLiability && balance < 0 ? 'Owed' : 'Balance',
                    style: context.text.labelMedium,
                  ),
                  AnimatedMoney(
                    balance,
                    style: context.text.displayMedium?.copyWith(
                      color: balance < 0 ? p.negative : p.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Update',
                      icon: Icons.tune_rounded,
                      height: 46,
                      onPressed: () => _updateBalance(context, ref, account, balance),
                    ),
                  ),
                  const Gap(Insets.sm),
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Transfer',
                      icon: Icons.swap_horiz_rounded,
                      height: 46,
                      onPressed: () => context.push('/txn/new?kind=transfer&account=$accountId'),
                    ),
                  ),
                  const Gap(Insets.sm),
                  Expanded(
                    child: AppButton(
                      label: 'Add',
                      icon: Icons.add_rounded,
                      height: 46,
                      onPressed: () => context.push('/txn/new?account=$accountId'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AppCard(
              margin: const EdgeInsets.fromLTRB(Insets.page, Insets.lg, Insets.page, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('In this month', style: context.text.labelMedium),
                        const Gap(2),
                        MoneyText(
                          inflow,
                          sign: true,
                          color: p.positive,
                          style: context.text.titleMedium,
                          tabular: false,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Out this month', style: context.text.labelMedium),
                        const Gap(2),
                        MoneyText(-outflow, style: context.text.titleMedium, tabular: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'History')),
          if (views != null && views.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions',
                message: 'Transactions in this account will show up here.',
                compact: true,
              ),
            )
          else if (views != null)
            ...txnDaySlivers(views, hidden: hidden, aboveNavBar: false),
          SliverToBoxAdapter(child: Gap(MediaQuery.paddingOf(context).bottom + Insets.xxl)),
        ],
      ),
    );
  }
}
