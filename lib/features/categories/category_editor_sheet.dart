import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/entity_icon.dart';
import 'package:spent/shared/widgets/pickers.dart';
import 'package:spent/shared/widgets/segmented.dart';
import 'package:spent/shared/widgets/sheets.dart';

/// Create or edit a category. Resolves to the category id on save.
Future<int?> showCategoryEditor(
  BuildContext context, {
  Category? category,
  CategoryKind kind = CategoryKind.expense,
}) => showAppSheet<int>(
  context,
  builder: (_) => _CategoryEditor(category: category, kind: kind),
);

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({required this.category, required this.kind});

  final Category? category;
  final CategoryKind kind;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.category?.name ?? '');
  late CategoryKind _kind = widget.category?.kind ?? widget.kind;
  late String _icon = widget.category?.icon ?? 'other';
  late int _color = widget.category?.color ?? EntityColors.blue.light.toARGB32();
  bool _saving = false;

  bool get _editing => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      Haptics.error();
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(categoryRepositoryProvider);
    int id;
    if (_editing) {
      await repo.save(widget.category!.copyWith(name: name, icon: _icon, color: _color));
      id = widget.category!.id;
    } else {
      id = await repo.add(name: name, kind: _kind, icon: _icon, color: _color);
    }
    Haptics.success();
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: _editing ? 'Edit category' : 'New category'),
        Flexible(
          child: CustomScrollView(
            shrinkWrap: true,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.page),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        EntityIcon(icon: _icon, color: _color, size: 56),
                        const Gap(Insets.lg),
                        Expanded(
                          child: TextField(
                            controller: _name,
                            autofocus: !_editing,
                            maxLength: 40,
                            textCapitalization: TextCapitalization.words,
                            style: context.text.titleMedium,
                            decoration: const InputDecoration(
                              hintText: 'Category name',
                              counterText: '',
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _save(),
                          ),
                        ),
                      ],
                    ),
                    if (!_editing) ...[
                      const Gap(Insets.lg),
                      SegmentedTabs<CategoryKind>(
                        values: CategoryKind.values,
                        selected: _kind,
                        labelOf: (k) => k.label,
                        onChanged: (k) => setState(() => _kind = k),
                      ),
                    ],
                    const Gap(Insets.xl),
                    Text('Color', style: context.text.labelMedium?.copyWith(color: p.ink3)),
                    const Gap(Insets.sm),
                    ColorSwatchPicker(
                      selected: _color,
                      onChanged: (c) => setState(() => _color = c),
                    ),
                    const Gap(Insets.sm),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: IconPickerGrid(
                  physics: const NeverScrollableScrollPhysics(),
                  selected: _icon,
                  color: _color,
                  onChanged: (k) => setState(() => _icon = k),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.page, Insets.lg),
          child: AppButton(
            label: _editing ? 'Save changes' : 'Create category',
            loading: _saving,
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
        ),
      ],
    );
  }
}
