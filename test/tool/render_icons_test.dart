// Renders the launcher icon set from the same painter the app uses.
//
//   RENDER_ICONS=1 flutter test test/tool/render_icons_test.dart
//   dart run flutter_launcher_icons
//
// Skipped unless RENDER_ICONS is set.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/shared/widgets/brand_logo.dart';

Future<void> _save(String path, int size, void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _layer(String path, LogoLayer layer, {double markScale = 1}) => _save(
  path,
  1024,
  (c) => SpentLogoPainter(layer: layer, markScale: markScale).paint(c, const Size.square(1024)),
);

const _adaptiveScale = 0.91;

/// Paints an adaptive layer the way the launcher composes it (16% inset).
void _adaptive(Canvas c, LogoLayer layer) {
  c.save();
  c.translate(1024 * 0.16, 1024 * 0.16);
  c.scale(0.68);
  SpentLogoPainter(layer: layer, markScale: _adaptiveScale).paint(c, const Size.square(1024));
  c.restore();
}

void main() {
  final enabled = Platform.environment['RENDER_ICONS'] != null;

  test('render icon set', () async {
    const dir = 'assets/icon';
    await _layer('$dir/icon.png', LogoLayer.full);
    await _layer('$dir/background.png', LogoLayer.background);
    // Android shows the middle 2/3 of an adaptive layer, and
    // flutter_launcher_icons insets the foreground by a further 16% per side,
    // so the mark is drawn large here to land at the intended size.
    await _layer('$dir/foreground.png', LogoLayer.foreground, markScale: _adaptiveScale);
    await _layer('$dir/monochrome.png', LogoLayer.monochrome, markScale: _adaptiveScale);
    // iOS 18 dark / tinted variants (transparent, the system adds the tile).
    await _layer('$dir/ios_dark.png', LogoLayer.foreground, markScale: 0.86);
    await _layer('$dir/ios_tinted.png', LogoLayer.monochrome, markScale: 0.86);

    // A review sheet: masks and small sizes on light and dark wallpapers.
    final preview = Platform.environment['ICON_PREVIEW'];
    if (preview == null) return;
    await _save(preview, 1400, (c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 1400, 700), Paint()..color = const Color(0xFFECEAE4));
      c.drawRect(const Rect.fromLTWH(0, 700, 1400, 700), Paint()..color = const Color(0xFF121418));
      for (final (y, dark) in [(60.0, false), (760.0, true)]) {
        // Squircle (iOS) at 420.
        c.save();
        c.translate(60, y);
        c.clipRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 420, 420),
            const Radius.circular(96),
          ),
        );
        const SpentLogoPainter().paint(c, const Size.square(420));
        c.restore();
        // Adaptive circle mask (Android) at 420: background + foreground.
        c.save();
        c.translate(540, y);
        c.clipPath(Path()..addOval(const Rect.fromLTWH(0, 0, 420, 420)));
        c.save();
        c.scale(420 / 1024 * 1.5);
        c.translate(-170.7, -170.7);
        const SpentLogoPainter(layer: LogoLayer.background).paint(c, const Size.square(1024));
        _adaptive(c, LogoLayer.foreground);
        c.restore();
        c.restore();
        // Small sizes.
        var x = 1020.0;
        for (final s in [180.0, 96.0, 48.0]) {
          c.save();
          c.translate(x, y + (180 - s) / 2);
          c.clipRSuperellipse(
            RSuperellipse.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.23)),
          );
          const SpentLogoPainter().paint(c, Size.square(s));
          c.restore();
          x += s + 24;
        }
        // Themed (monochrome) icon preview.
        c.save();
        c.translate(1020, y + 230);
        c.clipPath(Path()..addOval(const Rect.fromLTWH(0, 0, 180, 180)));
        c.drawRect(
          const Rect.fromLTWH(0, 0, 180, 180),
          Paint()..color = dark ? const Color(0xFF2E3B33) : const Color(0xFFCFE9DA),
        );
        c.scale(180 / 1024 * 1.5);
        c.translate(-170.7, -170.7);
        _adaptive(c, LogoLayer.monochrome);
        c.restore();
      }
    });
  }, skip: !enabled);
}
