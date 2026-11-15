import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/core/time/periods.dart';
import 'package:spent/data/models.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/activity/filter_sheet.dart';
import 'package:spent/features/transactions/txn_actions.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/txn_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialCategoryId});

  final int? initialCategoryId;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  late TxnFilter _filter = TxnFilter(
    categoryIds: widget.initialCategoryId == null ? const {} : {widget.initialCategoryId!},
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _filter = _filter.copyWith(query: q));
    });
  }

  Future<void> _openFilters() async {
    final f = await showFilterSheet(context, _filter);
    if (f != null && mounted) setState(() => _filter = f);
  }

  void _update(TxnFilter f) => setState(() => _filter = f);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categories = ref.watch(categoryMapProvider);
    final accounts = ref.watch(accountMapProvider);
    final hidden = ref.watch(pendingDeletionsProvider);
    final results = _filter.isEmpty ? null : ref.watch(searchResultsProvider(_filter)).value;
    final views = results == null ? null : TxnView.build(results, categories, accounts);
    final visible = views?.where((v) => !hidden.contains(v.txn.id)).toList();
    final spent = visible?.where((v) => v.isExpense).fold<int>(0, (s, v) => s + v.txn.amount) ?? 0;
    final earned = visible?.where((v) => v.isIncome).fold<int>(0, (s, v) => s + v.txn.amount) ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, Insets.sm),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
                  ),
                  const Gap(Insets.sm),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      autofocus: widget.initialCategoryId == null,
                      textInputAction: TextInputAction.search,
                      style: context.text.titleSmall,
                      onChanged: _onQuery,
                      decoration: InputDecoration(
                        hintText: 'Notes, categories, amounts…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 21),
                        suffixIcon: ListenableBuilder(
                          listenable: _query,
                          builder: (context, _) => _query.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () {
                                    _query.clear();
                                    _onQuery('');
                                  },
                                ),
                        ),
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
                          borderSide: BorderSide(color: p.ink.withValues(alpha: 0.7)),
                        ),
                      ),
                    ),
                  ),
                  const Gap(Insets.sm),
                  CircleIconButton(
                    icon: Icons.tune_rounded,
                    tooltip: 'Filters',
                    badge: _filter.hasFilters,
                    onPressed: _openFilters,
                  ),
                ],
              ),
            ),
            if (_filter.hasFilters) _ActiveFilters(filter: _filter, onChanged: _update),
            if (visible != null && visible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, 0),
                child: Row(
                  children: [
                    Text(
                      '${visible.length} result${visible.length == 1 ? '' : 's'}',
                      style: context.text.labelMedium,
                    ),
                    const Spacer(),
                    if (spent > 0) ...[
                      MoneyText(-spent, style: context.text.labelMedium, color: p.ink2),
                    ],
                    if (spent > 0 && earned > 0) Text('  ·  ', style: context.text.labelMedium),
                    if (earned > 0)
                      MoneyText(
                        earned,
                        sign: true,
                        style: context.text.labelMedium,
                        color: p.positive,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: visible == null
                  ? const EmptyState(
                      icon: Icons.manage_search_rounded,
                      title: 'Find anything',
                      message:
                          'Search by note, category, account or exact amount. Use filters for dates and types.',
                    )
                  : visible.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      message: 'Try a different word or loosen the filters.',
                    )
                  : CustomScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        if (_filter.sort == TxnSort.newest || _filter.sort == TxnSort.oldest)
                          ...txnDaySlivers(
                            visible,
                            hidden: hidden,
                            animate: false,
                            aboveNavBar: false,
                          )
                        else
                          SliverList.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, i) => SwipeToDelete(
                              txn: visible[i].txn,
                              aboveNavBar: false,
                              child: TxnTile(view: visible[i], showDate: true),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Gap(MediaQuery.paddingOf(context).bottom + Insets.xxl),
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

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.filter, required this.onChanged});

  final TxnFilter filter;
  final ValueChanged<TxnFilter> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryMapProvider);
    final accounts = ref.watch(accountMapProvider);
    final money = ref.watch(moneyFormatProvider);
    final chips = <(String, TxnFilter)>[
      for (final k in filter.kinds) (k.label, filter.copyWith(kinds: {...filter.kinds}..remove(k))),
      for (final id in filter.categoryIds)
        (
          categories[id]?.name ?? 'Category',
          filter.copyWith(categoryIds: {...filter.categoryIds}..remove(id)),
        ),
      for (final id in filter.accountIds)
        (
          accounts[id]?.name ?? 'Account',
          filter.copyWith(accountIds: {...filter.accountIds}..remove(id)),
        ),
      if (filter.from != null || filter.to != null)
        (
          rangeLabel(
            filter.from ?? DateTime(2000),
            (filter.to ?? DateTime.now()).subtract(const Duration(days: 1)),
          ),
          filter.copyWith(from: () => null, to: () => null),
        ),
      if (filter.minAmount != null || filter.maxAmount != null)
        (
          [
            if (filter.minAmount != null) '≥ ${money.format(filter.minAmount!)}',
            if (filter.maxAmount != null) '≤ ${money.format(filter.maxAmount!)}',
          ].join('  '),
          filter.copyWith(minAmount: () => null, maxAmount: () => null),
        ),
    ];
    final p = context.palette;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.page),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const Gap(Insets.sm),
        itemBuilder: (context, i) => Pressable(
          onTap: () => onChanged(chips[i].$2),
          child: Container(
            padding: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(chips[i].$1, style: context.text.labelMedium?.copyWith(color: p.accentText)),
                const Gap(4),
                Icon(Icons.close_rounded, size: 15, color: p.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
