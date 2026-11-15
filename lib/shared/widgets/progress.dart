import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/domain/analytics.dart';

/// Fill and track colors for a budget level. The track is a lighter step of
/// the same hue, so the state reads across the whole bar.
(Color fill, Color track) levelColors(BuildContext context, BudgetLevel level, {Color? okColor}) {
  final p = context.palette;
  return switch (level) {
    BudgetLevel.ok => (
      okColor ?? p.accent,
      (okColor ?? p.accent).withValues(alpha: p.isDark ? 0.2 : 0.14),
    ),
    BudgetLevel.warning => (p.warningFill, p.warningFill.withValues(alpha: p.isDark ? 0.22 : 0.16)),
    BudgetLevel.over => (p.negativeFill, p.negativeFill.withValues(alpha: p.isDark ? 0.22 : 0.14)),
  };
}

/// A horizontal meter that animates to [value] (0…1+). An optional [marker]
/// shows where spending "should" be today.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.height = 8,
    this.marker,
  });

  final double value;
  final Color color;
  final Color track;
  final double height;
  final double? marker;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
      duration: Motion.of(context, Motion.slower),
      curve: Motion.emphasized,
      builder: (context, v, _) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return SizedBox(
            height: math.max(height, marker != null ? height + 6 : height),
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
                Container(
                  height: height,
                  width: v <= 0 ? 0 : math.max(height, w * v),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
                if (marker != null && marker! > 0 && marker! < 1)
                  Positioned(
                    left: (w * marker!).clamp(1, w - 2) - 1,
                    child: Container(
                      width: 2,
                      height: height + 6,
                      decoration: BoxDecoration(
                        color: p.ink.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A circular progress ring that sweeps to [value] (0…1).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.size = 120,
    this.stroke = 12,
    this.child,
  });

  final double value;
  final Color color;
  final Color track;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
    duration: Motion.of(context, Motion.chart),
    curve: Motion.emphasized,
    builder: (context, v, child) => CustomPaint(
      size: Size.square(size),
      painter: _RingPainter(v, color, track, stroke),
      child: SizedBox.square(
        dimension: size,
        child: Center(child: child),
      ),
    ),
    child: child,
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base..color = track);
    if (value > 0) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}
