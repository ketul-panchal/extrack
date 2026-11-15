import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/buttons.dart';

/// "‹  October  ›" — the label slides in the direction you moved.
class PeriodSwitcher extends StatefulWidget {
  const PeriodSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.sublabel,
    this.canGoNext = true,
    this.onTapLabel,
  });

  final String label;
  final String? sublabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoNext;
  final VoidCallback? onTapLabel;

  @override
  State<PeriodSwitcher> createState() => _PeriodSwitcherState();
}

class _PeriodSwitcherState extends State<PeriodSwitcher> {
  int _direction = 1;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        CircleIconButton(
          icon: Icons.chevron_left_rounded,
          size: 40,
          tooltip: 'Previous',
          onPressed: () {
            setState(() => _direction = -1);
            widget.onPrevious();
          },
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTapLabel,
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.medium),
                switchInCurve: Motion.emphasized,
                switchOutCurve: Motion.exit,
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey('${widget.label}|${widget.sublabel}');
                  final dx = (incoming ? 0.25 : -0.25) * _direction;
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  key: ValueKey('${widget.label}|${widget.sublabel}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (widget.sublabel != null)
                      Text(
                        widget.sublabel!,
                        style: context.text.bodySmall?.copyWith(color: p.ink3),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        CircleIconButton(
          icon: Icons.chevron_right_rounded,
          size: 40,
          tooltip: 'Next',
          onPressed: widget.canGoNext
              ? () {
                  setState(() => _direction = 1);
                  widget.onNext();
                }
              : null,
        ),
      ],
    );
  }
}
