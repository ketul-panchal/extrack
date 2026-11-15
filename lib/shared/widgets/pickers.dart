import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_icons.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/pressable.dart';

/// A row of entity color swatches.
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({super.key, required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in EntityColors.all)
          Pressable(
            onTap: () => onChanged(c.light.toARGB32()),
            pressedScale: 0.88,
            semanticLabel: c.name,
            child: AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.standard,
              width: 38,
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == c.light.toARGB32()
                      ? c.resolve(p.brightness)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.resolve(p.brightness), shape: BoxShape.circle),
                child: AnimatedSwitcher(
                  duration: Motion.fast,
                  child: selected == c.light.toARGB32()
                      ? const Icon(
                          Icons.check_rounded,
                          key: ValueKey(true),
                          color: Colors.white,
                          size: 18,
                        )
                      : const SizedBox.shrink(key: ValueKey(false)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// All icons, grouped, in a grid. Shown inside a sheet.
class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({
    super.key,
    required this.selected,
    required this.color,
    required this.onChanged,
    this.physics,
  });

  final String selected;
  final int color;
  final ValueChanged<String> onChanged;

  /// Pass [NeverScrollableScrollPhysics] when embedding inside another scroll view.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = p.entity(color);
    return CustomScrollView(
      shrinkWrap: true,
      primary: physics == null ? null : false,
      physics: physics,
      slivers: [
        for (final group in AppIcons.groups.entries) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, Insets.lg, Insets.page, Insets.sm),
              child: Text(group.key, style: context.text.labelMedium?.copyWith(color: p.ink3)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.page - 4),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 58,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: group.value.length,
              itemBuilder: (context, i) {
                final key = group.value[i];
                final isSelected = key == selected;
                return Pressable(
                  pressedScale: 0.88,
                  onTap: () {
                    Haptics.selection();
                    onChanged(key);
                  },
                  child: AnimatedContainer(
                    duration: Motion.medium,
                    decoration: ShapeDecoration(
                      color: isSelected ? c : p.surface2,
                      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Icon(
                      AppIcons.of(key),
                      size: 24,
                      color: isSelected ? Colors.white : p.ink2,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SliverToBoxAdapter(child: Gap(Insets.xl)),
      ],
    );
  }
}
