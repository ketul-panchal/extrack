import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/categories/category_editor_sheet.dart';
import 'package:spent/features/pickers/picker_sheets.dart';
import 'package:spent/shared/widgets/app_card.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/sections.dart';
import 'package:spent/shared/widgets/segmented.dart';
import 'package:spent/shared/widgets/sheets.dart';
import 'package:spent/shared/widgets/toast.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryKind _kind = CategoryKind.expense;
  List<Category>? _dragOrder;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final active = _dragOrder ?? all.where((c) => c.kind == _kind && !c.archived).toList();
    final archived = all.where((c) => c.kind == _kind && c.archived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New category',
            onPressed: () => showCategoryEditor(context, kind: _kind),
          ),
          const Gap(Insets.sm),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, Insets.md),
              child: SegmentedTabs<CategoryKind>(
                values: CategoryKind.values,
                selected: _kind,
                labelOf: (k) => k.label,
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.sm),
              child: Text(
                'Hold and drag to reorder. The editor also learns your most used ones.',
                style: context.text.bodySmall?.copyWith(color: p.ink3),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.page),
            sliver: SliverReorderableList(
              itemCount: active.length,
              proxyDecorator: (child, index, animation) => AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Transform.scale(
                  scale: 1 + 0.03 * Curves.easeOut.transform(animation.value),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8 * animation.value,
                    shadowColor: p.shadow.withValues(alpha: 0.3),
                    borderRadius: Radii.card,
                    child: child,
                  ),
                ),
                child: child,
              ),
              onReorderStart: (_) => Haptics.medium(),
              onReorderItem: (from, to) async {
                final list = [...active];
                final item = list.removeAt(from);
                list.insert(to, item);
                setState(() => _dragOrder = list);
                await ref.read(categoryRepositoryProvider).reorder([for (final c in list) c.id]);
                if (mounted) setState(() => _dragOrder = null);
              },
              itemBuilder: (context, i) {
                final c = active[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(c.id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      onTap: () => context.push('/categories/${c.id}'),
                      child: Row(
                        children: [
                          EntityIcon(icon: c.icon, color: c.color, size: 40),
                          const Gap(Insets.md),
                          Expanded(child: Text(c.name, style: context.text.titleSmall)),
                          IconButton(
                            icon: Icon(Icons.more_horiz_rounded, color: p.ink3),
                            tooltip: 'Options',
                            onPressed: () => categoryActions(context, ref, c),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(Icons.drag_indicator_rounded, color: p.ink3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (archived.isNotEmpty) ...[
            const SliverToBoxAdapter(child: GroupLabel('Archived')),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page),
              sliver: SliverList.list(
                children: [
                  for (final c in archived)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Insets.sm),
                      child: Opacity(
                        opacity: 0.65,
                        child: AppCard(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          child: Row(
                            children: [
                              EntityIcon(icon: c.icon, color: c.color, size: 40),
                              const Gap(Insets.md),
                              Expanded(child: Text(c.name, style: context.text.titleSmall)),
                              TextButton(
                                onPressed: () =>
                                    ref.read(categoryRepositoryProvider).setArchived(c.id, false),
                                child: const Text('Restore'),
                              ),
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

/// Edit / archive / delete menu for a category. Shared with the detail screen.
Future<void> categoryActions(
  BuildContext context,
  WidgetRef ref,
  Category c, {
  bool popOnDelete = false,
}) async {
  final action = await showAppSheet<String>(
    context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: c.name),
        OptionRow(
          leading: const Icon(Icons.edit_outlined),
          title: 'Edit',
          onTap: () => Navigator.pop(ctx, 'edit'),
        ),
        OptionRow(
          leading: const Icon(Icons.archive_outlined),
          title: 'Archive',
          subtitle: 'Hide it from pickers; keep its history',
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
  final repo = ref.read(categoryRepositoryProvider);
  switch (action) {
    case 'edit':
      await showCategoryEditor(context, category: c);
    case 'archive':
      await repo.setArchived(c.id, true);
      if (context.mounted) {
        AppToast.show(
          context,
          '${c.name} archived',
          icon: Icons.archive_outlined,
          actionLabel: 'Undo',
          onAction: () => repo.setArchived(c.id, false),
        );
      }
    case 'delete':
      final count = await ref.read(txnRepositoryProvider).countForCategory(c.id);
      if (!context.mounted) return;
      int? moveTo;
      if (count > 0) {
        final choice = await showAppSheet<String>(
          context,
          builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                title: 'Delete ${c.name}?',
                subtitle:
                    'It has $count transaction${count == 1 ? '' : 's'}. What should happen to them?',
              ),
              OptionRow(
                leading: const Icon(Icons.drive_file_move_outline),
                title: 'Move them to another category',
                onTap: () => Navigator.pop(ctx, 'move'),
              ),
              OptionRow(
                leading: const Icon(Icons.archive_outlined),
                title: 'Archive instead',
                subtitle: 'Recommended: keeps your history intact',
                onTap: () => Navigator.pop(ctx, 'archive'),
              ),
              OptionRow(
                leading: Icon(Icons.help_outline_rounded, color: ctx.palette.negative),
                title: 'Leave them uncategorized',
                destructive: true,
                onTap: () => Navigator.pop(ctx, 'orphan'),
              ),
              const Gap(Insets.md),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;
        if (choice == 'archive') {
          await repo.setArchived(c.id, true);
          if (popOnDelete && context.mounted) context.pop();
          return;
        }
        if (choice == 'move') {
          moveTo = await pickCategory(context, kind: c.kind);
          if (moveTo == null || moveTo == c.id || !context.mounted) return;
        }
      } else {
        final ok = await confirmSheet(
          context,
          title: 'Delete ${c.name}?',
          message: 'This category has no transactions.',
        );
        if (!ok || !context.mounted) return;
      }
      if (popOnDelete) context.pop();
      await repo.delete(c.id, moveTo: moveTo);
      Haptics.medium();
  }
}
