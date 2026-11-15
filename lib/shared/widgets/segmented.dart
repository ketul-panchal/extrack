import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';

/// A pill segmented control whose thumb glides between options.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    this.height = 42,
    this.thumbColor,
    this.selectedLabelColor,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final double height;
  final Color? thumbColor;
  final Color? selectedLabelColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(Radii.pill)),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.of(context, Motion.slow),
                curve: Motion.emphasized,
                left: index * w,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: thumbColor ?? (p.isDark ? p.surface3 : p.surface),
                    borderRadius: BorderRadius.circular(Radii.pill),
                    boxShadow: p.isDark
                        ? null
                        : [
                            BoxShadow(
                              color: p.shadow.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final v in values)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: v == selected,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (v == selected) return;
                            Haptics.selection();
                            onChanged(v);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: Motion.medium,
                              style: context.text.titleSmall!.copyWith(
                                color: v == selected ? (selectedLabelColor ?? p.ink) : p.ink2,
                                fontWeight: v == selected ? FontWeight.w700 : FontWeight.w600,
                              ),
                              child: Text(labelOf(v), maxLines: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
