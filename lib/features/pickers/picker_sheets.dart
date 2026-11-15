import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/categories/category_editor_sheet.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/money_text.dart';
import 'package:spent/shared/widgets/pressable.dart';
import 'package:spent/shared/widgets/sheets.dart';

/// Grid of categories of [kind]; resolves to the chosen id.
Future<int?> pickCategory(BuildContext context, {required CategoryKind kind, int? selected}) =>
    showAppSheet<int>(
      context,
      builder: (_) => _CategoryPicker(kind: kind, selected: selected),
    );

class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({required this.kind, required this.selected});

  final CategoryKind kind;
  final int? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesOfKindProvider(kind));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: 'Category',
          trailing: AppButton.ghost(
            label: 'New',
            icon: Icons.add_rounded,
            onPressed: () async {
              final id = await showCategoryEditor(context, kind: kind);
              if (id != null && context.mounted) Navigator.pop(context, id);
            },
          ),
        ),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Insets.md, 0, Insets.md, Insets.xl),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 96,
              mainAxisExtent: 98,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final c = categories[i];
              final isSelected = c.id == selected;
              return Pressable(
                pressedScale: 0.92,
                onTap: () {
                  Haptics.selection();
                  Navigator.pop(context, c.id);
                },
                child: Column(
                  children: [
                    const Gap(6),
                    EntityIcon(icon: c.icon, color: c.color, size: 52, filled: isSelected),
                    const Gap(8),
                    Text(
                      c.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: isSelected ? context.palette.ink : context.palette.ink2,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// List of accounts with balances; resolves to the chosen id.
Future<int?> pickAccount(
  BuildContext context, {
  int? selected,
  int? exclude,
  String title = 'Account',
}) => showAppSheet<int>(
  context,
  builder: (_) => _AccountPicker(selected: selected, exclude: exclude, title: title),
);

class _AccountPicker extends ConsumerWidget {
  const _AccountPicker({required this.selected, required this.exclude, required this.title});

  final int? selected;
  final int? exclude;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider).where((a) => a.id != exclude).toList();
    final balances = ref.watch(balancesProvider).value ?? const {};
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: title),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: Insets.lg),
            children: [
              for (final a in accounts)
                OptionRow(
                  leading: EntityIcon(
                    icon: a.icon,
                    color: a.color,
                    size: 42,
                    filled: a.id == selected,
                  ),
                  title: a.name,
                  subtitle: a.type.label,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MoneyText(
                        balances[a.id] ?? a.openingBalance,
                        style: context.text.titleSmall,
                        color: context.palette.ink2,
                      ),
                      if (a.id == selected) ...[
                        const Gap(Insets.sm),
                        Icon(Icons.check_rounded, color: context.palette.accentText, size: 20),
                      ],
                    ],
                  ),
                  onTap: () {
                    Haptics.selection();
                    Navigator.pop(context, a.id);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
