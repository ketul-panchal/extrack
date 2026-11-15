// Renders the main screens to PNGs for visual review.
//
//   SCREENSHOTS=/path/to/dir flutter test test/screenshots_test.dart
//
// Skipped unless SCREENSHOTS is set.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/app/app.dart';
import 'package:spent/app/router.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/services/sample_data.dart';
import 'package:spent/core/settings/stores.dart';
import 'package:spent/data/recurring_repository.dart';

import 'helpers.dart';

final _outDir = Platform.environment['SCREENSHOTS'];

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final loader = FontLoader(family.startsWith('packages/') ? family.split('/').last : family);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

class _Shooter {
  _Shooter(this.tester, this.key, this.prefix);

  final WidgetTester tester;
  final GlobalKey key;
  final String prefix;

  Future<void> settle([int ms = 1400]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(String name) async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/$prefix-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }
}

Future<void> _run(WidgetTester tester, {required bool dark, required String prefix}) async {
  debugDisableShadows = false;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);

  final db = memoryDatabase();
  await tester.runAsync(() async {
    await _loadFonts();
    await SampleData(db, Currency.byCode('INR')).load();
    await RecurringRepository(db).processDue(DateTime.now());
  });
  final store = MemoryKeyValueStore({
    'settings.onboarded': true,
    'settings.name': 'Jay',
    'settings.currencyCode': 'INR',
    'settings.numberStyle': 'indian',
    'settings.themeMode': dark ? 'dark' : 'light',
  });
  final key = GlobalKey();
  final container = ProviderContainer(
    overrides: testOverrides(db: db, store: store),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: UncontrolledProviderScope(container: container, child: const SpentApp()),
    ),
  );
  final s = _Shooter(tester, key, prefix);
  final router = container.read(routerProvider);
  await s.settle(1800);
  await s.shot('01-home');

  await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -700));
  await s.settle(800);
  await s.shot('02-home-scrolled');

  router.go('/activity');
  await s.settle();
  await s.shot('03-activity');
  await tester.tap(find.byTooltip('Calendar view'));
  await s.settle();
  await s.shot('04-activity-calendar');

  router.go('/plan');
  await s.settle();
  await s.shot('05-plan-budgets');
  router.go('/plan?tab=goals');
  await s.settle();
  await s.shot('06-plan-goals');
  router.go('/plan?tab=bills');
  await s.settle();
  await s.shot('07-plan-bills');

  router.go('/insights');
  await s.settle(1800);
  await s.shot('08-insights');
  await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -760));
  await s.settle(1600);
  await s.shot('09-insights-2');
  await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -900));
  await s.settle(1600);
  await s.shot('10-insights-3');

  router.go('/home');
  await s.settle(600);
  unawaited(router.push('/txn/new'));
  await s.settle();
  for (final k in ['1', '2', '5', '0']) {
    await tester.tap(find.text(k).last);
    await tester.pump(const Duration(milliseconds: 80));
  }
  await s.settle(800);
  await s.shot('11-editor');
  router.pop();
  await s.settle(800);

  unawaited(router.push('/settings'));
  await s.settle();
  await s.shot('12-settings');
  router.pop();
  await s.settle(600);

  unawaited(router.push('/accounts'));
  await s.settle();
  await s.shot('13-accounts');
  router.pop();
  await s.settle(600);

  final food = (await tester.runAsync(
    () => db.select(db.categories).get(),
  ))!.firstWhere((c) => c.name == 'Food & Dining');
  unawaited(router.push('/categories/${food.id}'));
  await s.settle(1600);
  await s.shot('14-category');
  router.pop();
  await s.settle(600);

  unawaited(router.push('/search'));
  await s.settle(600);
  await tester.enterText(find.byType(TextField).first, 'coffee');
  await s.settle(1200);
  await s.shot('15-search');

  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.runAsync(db.close);
  debugDisableShadows = true;
}

void main() {
  final skip = _outDir == null ? 'Set SCREENSHOTS=<dir> to render screenshots' : null;

  testWidgets('light', (tester) => _run(tester, dark: false, prefix: 'light'), skip: skip != null);
  testWidgets('dark', (tester) => _run(tester, dark: true, prefix: 'dark'), skip: skip != null);

  testWidgets('onboarding', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);
    final db = memoryDatabase();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: testOverrides(db: db),
          child: const SpentApp(),
        ),
      ),
    );
    final s = _Shooter(tester, key, 'light');
    await s.settle(2000);
    await s.shot('00-welcome');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
    debugDisableShadows = true;
  }, skip: skip != null);
}
