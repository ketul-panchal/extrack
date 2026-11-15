import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/accounts/account_editor_sheet.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/sections.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key, this.openNew = false});

  final bool openNew;

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  List<Account>? _dragOrder;

  @override
  void initState() {
    super.initState();
    if (widget.openNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(showAccountEditor(context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = ref.watch(accountsProvider).value ?? const <Account>[];
    final balances = ref.watch(balancesProvider).value ?? const <int, int>{};
    final defaultId = ref.watch(settingsProvider.select((s) => s.defaultAccountId));
    final active = _dragOrder ?? all.where((a) => !a.archived).toList();
    final archived = all.where((a) => a.archived).toList();
    var assets = 0;
    var owed = 0;
    for (final a in active.where((a) => a.includeInTotal)) {
      final b = balances[a.id] ?? a.openingBalance;
      if (b >= 0) {
        assets += b;
      } else {
        owed += -b;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New account',
            onPressed: () => showAccountEditor(context),
          ),
          const Gap(Insets.sm),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: FadeSlideIn(
              child: AppCard(
                margin: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, Insets.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net worth', style: context.text.labelMedium),
                    const Gap(4),
                    AnimatedMoney(assets - owed, style: context.text.displaySmall),
                    const Gap(Insets.md),
                    Row(
                      children: [
                        Expanded(
                          child: _Mini(label: 'You have', amount: assets, color: p.ink),
                        ),
                        Expanded(
                          child: _Mini(
                            label: 'You owe',
                            amount: owed,
                            color: owed > 0 ? p.negative : p.ink,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.page),
            sliver: SliverReorderableList(
              itemCount: active.length,
              onReorderStart: (_) => Haptics.medium(),
              onReorderItem: (from, to) async {
                final list = [...active];
                final item = list.removeAt(from);
                list.insert(to, item);
                setState(() => _dragOrder = list);
                await ref.read(accountRepositoryProvider).reorder([for (final a in list) a.id]);
                if (mounted) setState(() => _dragOrder = null);
              },
              proxyDecorator: (child, _, animation) => Material(
                color: Colors.transparent,
                elevation: 8 * animation.value,
                shadowColor: p.shadow.withValues(alpha: 0.3),
                borderRadius: Radii.card,
                child: child,
              ),
              itemBuilder: (context, i) {
                final a = active[i];
                final balance = balances[a.id] ?? a.openingBalance;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(a.id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: FadeSlideIn(
                      index: i + 1,
                      child: AppCard(
                        onTap: () => context.push('/accounts/${a.id}'),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            EntityIcon(icon: a.icon, color: a.color, size: 44),
                            const Gap(Insets.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.name, style: context.text.titleSmall),
                                  const Gap(2),
                                  Text(
                                    [
                                      a.type.label,
                                      if (a.id == defaultId) 'Default',
                                      if (!a.includeInTotal) 'Not in total',
                                    ].join(' · '),
                                    style: context.text.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            MoneyText(
                              balance,
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              color: balance < 0 ? p.negative : p.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (active.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts',
                message: 'Add the places you keep money: cash, bank, cards or wallets.',
                actionLabel: 'Add account',
                onAction: () => showAccountEditor(context),
              ),
            ),
          if (archived.isNotEmpty) ...[
            const SliverToBoxAdapter(child: GroupLabel('Archived')),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page),
              sliver: SliverList.list(
                children: [
                  for (final a in archived)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Insets.sm),
                      child: Opacity(
                        opacity: 0.6,
                        child: AppCard(
                          onTap: () => context.push('/accounts/${a.id}'),
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              EntityIcon(icon: a.icon, color: a.color, size: 40),
                              const Gap(Insets.md),
                              Expanded(child: Text(a.name, style: context.text.titleSmall)),
                              MoneyText(balances[a.id] ?? a.openingBalance, color: p.ink2),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          SliverToBoxAdapter(child: Gap(MediaQuery.paddingOf(context).bottom + Insets.xxl)),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.amount, required this.color});

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.text.labelSmall?.copyWith(letterSpacing: 0.1)),
      const Gap(2),
      MoneyText(
        amount,
        color: color,
        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        tabular: false,
      ),
    ],
  );
}
