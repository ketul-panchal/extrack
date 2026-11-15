import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:spent/app/shell.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/features/accounts/account_detail_screen.dart';
import 'package:spent/features/accounts/accounts_screen.dart';
import 'package:spent/features/activity/activity_screen.dart';
import 'package:spent/features/activity/search_screen.dart';
import 'package:spent/features/categories/categories_screen.dart';
import 'package:spent/features/categories/category_detail_screen.dart';
import 'package:spent/features/home/home_screen.dart';
import 'package:spent/features/insights/insights_screen.dart';
import 'package:spent/features/onboarding/onboarding_screen.dart';
import 'package:spent/features/plan/goal_detail_screen.dart';
import 'package:spent/features/plan/plan_screen.dart';
import 'package:spent/features/plan/rule_detail_screen.dart';
import 'package:spent/features/plan/rule_editor_screen.dart';
import 'package:spent/features/settings/settings_screen.dart';
import 'package:spent/features/transactions/editor/txn_editor_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Slides up and fades in, like a sheet that fills the screen.
Page<void> _modal(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  fullscreenDialog: true,
  transitionDuration: Motion.slow,
  reverseTransitionDuration: Motion.medium,
  transitionsBuilder: (context, animation, secondary, child) {
    final slide = CurvedAnimation(
      parent: animation,
      curve: Motion.emphasized,
      reverseCurve: Motion.exit,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.5),
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.14), end: Offset.zero).animate(slide),
        child: child,
      ),
    );
  },
);

Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: Motion.slower,
  transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  ),
);

TxnKind _kind(String? s) =>
    TxnKind.values.firstWhere((k) => k.name == s, orElse: () => TxnKind.expense);

final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<bool>(ref.read(settingsProvider).onboarded);
  ref.listen(settingsProvider.select((s) => s.onboarded), (_, v) => onboarded.value = v);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    observers: [PosthogObserver()],
    refreshListenable: onboarded,
    redirect: (context, state) {
      final atWelcome = state.matchedLocation == '/welcome';
      if (!onboarded.value) return atWelcome ? null : '/welcome';
      if (atWelcome) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', pageBuilder: (_, s) => _fade(s, const OnboardingScreen())),
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            BranchSwitcher(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', pageBuilder: (_, s) => _fade(s, const HomeScreen()))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plan',
                builder: (_, s) => PlanScreen(initialTab: s.uri.queryParameters['tab']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/txn/new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _modal(
          s,
          TxnEditorScreen(
            initialKind: _kind(s.uri.queryParameters['kind']),
            initialCategoryId: int.tryParse(s.uri.queryParameters['category'] ?? ''),
            initialAccountId: int.tryParse(s.uri.queryParameters['account'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/txn/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) =>
            _modal(s, TxnEditorScreen(txnId: int.parse(s.pathParameters['id']!))),
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) =>
            SearchScreen(initialCategoryId: int.tryParse(s.uri.queryParameters['category'] ?? '')),
      ),
      GoRoute(
        path: '/accounts',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => AccountsScreen(openNew: s.uri.queryParameters['new'] == '1'),
        routes: [
          GoRoute(
            path: ':id',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, s) => AccountDetailScreen(accountId: int.parse(s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/categories',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const CategoriesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, s) => CategoryDetailScreen(categoryId: int.parse(s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/recurring/new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _modal(s, const RuleEditorScreen()),
      ),
      GoRoute(
        path: '/recurring/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => RuleDetailScreen(ruleId: int.parse(s.pathParameters['id']!)),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (_, s) =>
                _modal(s, RuleEditorScreen(ruleId: int.parse(s.pathParameters['id']!))),
          ),
        ],
      ),
      GoRoute(
        path: '/goals/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => GoalDetailScreen(goalId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    onboarded.dispose();
  });
  return router;
});
