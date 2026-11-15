import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';

/// A short confetti burst over everything. Skipped when reduced motion is on.
abstract final class Celebration {
  static void show(BuildContext context) {
    if (Motion.reduced(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _Confetti(onDone: () => entry.remove()));
    overlay.insert(entry);
  }
}

class _Particle {
  _Particle(math.Random r, Size size, this.color)
    : x = size.width / 2 + (r.nextDouble() - 0.5) * 80,
      y = size.height * 0.42,
      vx = (r.nextDouble() - 0.5) * 900,
      vy = -500 - r.nextDouble() * 700,
      spin = (r.nextDouble() - 0.5) * 14,
      w = 6 + r.nextDouble() * 6,
      h = 10 + r.nextDouble() * 8,
      round = r.nextBool();

  double x, y, vx, vy, angle = 0;
  final double spin, w, h;
  final bool round;
  final Color color;
}

class _Confetti extends StatefulWidget {
  const _Confetti({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  List<_Particle>? _particles;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.forward().whenComplete(widget.onDone);
  }

  void _tick() {
    final elapsed = _c.lastElapsedDuration ?? Duration.zero;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    for (final p in _particles ?? const <_Particle>[]) {
      p.vy += 1500 * dt;
      p.vx *= 0.985;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.angle += p.spin * dt;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, c) {
        final brightness = Theme.of(context).brightness;
        _particles ??= () {
          final r = math.Random();
          final colors = EntityColors.all.map((e) => e.resolve(brightness)).toList();
          return [for (var i = 0; i < 90; i++) _Particle(r, c.biggest, colors[i % colors.length])];
        }();
        return CustomPaint(
          size: c.biggest,
          painter: _ConfettiPainter(_particles!, 1 - Curves.easeIn.transform(_c.value)),
        );
      },
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.opacity);

  final List<_Particle> particles;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      paint.color = p.color.withValues(alpha: opacity.clamp(0, 1));
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.angle);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.w / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}
