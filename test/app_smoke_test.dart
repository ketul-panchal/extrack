import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/app/app.dart';
import 'package:spent/app/router.dart';
import 'package:spent/core/settings/settings.dart';

import 'helpers.dart';

/// Walks through the whole app on a phone-sized screen. Any exception or
/// layout overflow along the way fails the test.
void main() {
  testWidgets('first run → sample data → every screen', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = memoryDatabase();
    final container = ProviderContainer(overrides: testOverrides(db: db));
    addTearDown(container.dispose);

    Future<void> settle([int ms = 1200]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Lets real database work finish between frames.
    Future<void> settleWithIo([int rounds = 6]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SpentApp()));
    await settle(1500);
    expect(find.text('Get started'), findsOneWidget);

    // Walk the setup pages, then go back and take the sample-data path.
    await tester.tap(find.text('Get started'));
    await settle();
    expect(find.text('Make it yours'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle();
    expect(find.text('Where\'s your money?'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle();
    await tester.tap(find.byTooltip('Back'));
    await settle();

    await tester.tap(find.text('Explore with sample data'));
    await settleWithIo(30);
    await settle(1500);
    expect(container.read(settingsProvider).onboarded, isTrue);
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);

    final router = container.read(routerProvider);
    Future<void> visit(String location, {bool push = false}) async {
      if (push) {
        unawaited(router.push(location));
      } else {
        router.go(location);
      }
      await settleWithIo();
      await settle(1500);
    }

    await visit('/activity');
    expect(find.text('Activity'), findsWidgets);
    await tester.tap(find.byTooltip('Calendar view'));
    await settle();
    expect(find.text('More spent'), findsOneWidget);

    await visit('/plan');
    expect(find.text('Monthly budget'), findsOneWidget);
    await visit('/plan?tab=goals');
    expect(find.text('Emergency fund'), findsOneWidget);
    await visit('/plan?tab=bills');
    expect(find.text('Monthly commitments'), findsOneWidget);

    await visit('/insights');
    expect(find.text('Spending'), findsWidgets);
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -1200));
    await settle();
    await tester.tap(find.text('Year'));
    await settleWithIo();
    await settle(1500);

    // Add an expense with the keypad.
    await visit('/home');
    await visit('/txn/new', push: true);
    for (final k in ['4', '2', '0']) {
      await tester.tap(find.text(k).last);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('Food & Dining').first);
    await settle(400);
    await tester.tap(find.text('Add expense'));
    await settleWithIo(10);
    await settle(1500);
    final added = await tester.runAsync(
      () => (db.select(db.txns)..where((t) => t.amount.equals(42000))).get(),
    );
    expect(added, hasLength(1));

    final firstCategory = (await tester.runAsync(() => db.select(db.categories).get()))!.first;
    final firstAccount = (await tester.runAsync(() => db.select(db.accounts).get()))!.first;
    final firstGoal = (await tester.runAsync(() => db.select(db.goals).get()))!.first;
    final firstRule = (await tester.runAsync(() => db.select(db.recurringRules).get()))!.first;
    for (final location in [
      '/settings',
      '/accounts',
      '/accounts/${firstAccount.id}',
      '/categories',
      '/categories/${firstCategory.id}',
      '/goals/${firstGoal.id}',
      '/recurring/${firstRule.id}',
      '/txn/${added!.single.id}',
      '/search',
    ]) {
      await visit(location, push: true);
      router.pop();
      await settle(800);
    }

    // Dark mode renders too.
    await container.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: ThemeMode.dark));
    await visit('/home');
    await visit('/insights');

    await tester.pumpWidget(const SizedBox());
    await settle(200);
    await tester.runAsync(db.close);
  });

  testWidgets('a fresh start with your own accounts', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 690 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final container = ProviderContainer(overrides: testOverrides(db: db));
    addTearDown(container.dispose);

    Future<void> settle([int ms = 1000]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SpentApp()));
    await settle(1500);
    // Short screen: the welcome page scrolls.
    await tester.ensureVisible(find.text('Get started'));
    await settle(300);
    await tester.tap(find.text('Get started'));
    await settle();
    await tester.tap(find.text('Continue'));
    await settle();
    await tester.enterText(find.byType(TextField).at(1), '25000');
    await tester.tap(find.text('Continue'));
    await settle();
    await tester.enterText(find.byType(TextField).first, '30000');
    await tester.tap(find.text('Start using Spent'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await settle(1500);
    expect(container.read(settingsProvider).onboarded, isTrue);
    final accounts = await tester.runAsync(() => db.select(db.accounts).get());
    expect(accounts!.map((a) => a.name), ['Cash', 'Bank account']);
    final budgets = await tester.runAsync(() => db.select(db.budgets).get());
    expect(budgets!.single.categoryId, isNull);
    expect(find.text('Nothing here yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(200);
    await tester.runAsync(db.close);
  });
}
