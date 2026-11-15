import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Which parts of the logo to draw. The launcher icon set is rendered from
/// these same layers, so the app and its icon always match.
enum LogoLayer {
  /// Background tile and mark: the full icon (iOS, legacy Android, in-app).
  full,

  /// Only the tile (Android adaptive background).
  background,

  /// Only the mark on transparent (Android adaptive foreground).
  foreground,

  /// The mark in white on transparent (Android 13 themed icon).
  monochrome,
}

/// The Spent mark: a flowing "S" — money moving — that ends in a marker dot,
/// the same end-dot the app's pace chart uses. Drawn on a 1024 grid.
class SpentLogoPainter extends CustomPainter {
  const SpentLogoPainter({this.layer = LogoLayer.full, this.markScale = 1});

  final LogoLayer layer;

  /// Shrinks the mark around the center (adaptive icons need a safe margin).
  final double markScale;

  static const ink = Color(0xFF16181C);
  static const inkDeep = Color(0xFF0B0C0F);
  static const mint = Color(0xFF8BF5CC);
  static const emerald = Color(0xFF10B981);
  static const lime = Color(0xFFD9F99D);

  static double _rad(double deg) => deg * math.pi / 180;

  /// The "S": two arcs that meet tangentially at the center.
  static Path markPath() => Path()
    ..addArc(Rect.fromCircle(center: const Offset(512, 376), radius: 136), _rad(-28), _rad(-242))
    ..arcTo(
      Rect.fromCircle(center: const Offset(512, 648), radius: 136),
      _rad(-90),
      _rad(236),
      false,
    );

  static Offset get _end {
    const a = (-90 + 236) * math.pi / 180;
    return Offset(512 + 136 * math.cos(a), 648 + 136 * math.sin(a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 1024;
    canvas.save();
    canvas.scale(scale);
    const square = Rect.fromLTWH(0, 0, 1024, 1024);

    if (layer == LogoLayer.full || layer == LogoLayer.background) {
      canvas.drawRect(
        square,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C3139), ink, inkDeep],
            stops: [0, 0.55, 1],
          ).createShader(square),
      );
      // Soft emerald glow from the top right, like the balance card.
      const glowCenter = Offset(880, 120);
      canvas.drawCircle(
        glowCenter,
        560,
        Paint()
          ..shader = RadialGradient(
            colors: [emerald.withValues(alpha: 0.42), emerald.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: glowCenter, radius: 560)),
      );
    }

    if (layer != LogoLayer.background) {
      final mono = layer == LogoLayer.monochrome;
      canvas.translate(512, 512);
      canvas.scale(markScale);
      canvas.translate(-512, -512);

      const strokeWidth = 108.0;
      const dotRadius = 66.0;
      const gap = 20.0;
      final end = _end;

      // Stroke, with a clean gap cut around the end dot.
      canvas.saveLayer(square.inflate(200), Paint());
      canvas.drawPath(
        markPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white
          ..shader = mono
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [mint, emerald],
                ).createShader(const Rect.fromLTRB(320, 180, 704, 840)),
      );
      canvas.drawCircle(end, dotRadius + gap, Paint()..blendMode = BlendMode.clear);
      canvas.restore();

      canvas.drawCircle(end, dotRadius, Paint()..color = mono ? Colors.white : lime);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpentLogoPainter old) => old.layer != layer || old.markScale != markScale;
}

/// The full logo as a rounded tile, for use inside the app.
class SpentLogo extends StatelessWidget {
  const SpentLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: BorderRadius.circular(size * 0.27),
    child: CustomPaint(size: Size.square(size), painter: const SpentLogoPainter()),
  );
}
