import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../features/bills/bills_page.dart';
import '../features/budgets/budgets_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/goals/goal_detail_page.dart';
import '../features/goals/goals_page.dart';
import '../features/household/household_page.dart';
import '../features/insights/insights_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/recurring/recurring_page.dart';
import '../features/settings/categories_page.dart';
import '../features/settings/profile_page.dart';
import '../features/transactions/history_page.dart';
import '../features/wallets/wallets_page.dart';
import 'shell.dart';

const onboardedKey = 'onboarded';

final routerProvider = Provider<GoRouter>((ref) {
  final prefs = ref.read(prefsProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final onboarded = prefs.getBool(onboardedKey) ?? false;
      if (!onboarded && state.matchedLocation != '/onboarding') return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', pageBuilder: (c, s) => _fade(s, const OnboardingPage())),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (c, s) => const DashboardPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/insights', builder: (c, s) => const InsightsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/goals', builder: (c, s) => const GoalsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfilePage())]),
        ],
      ),
      GoRoute(path: '/history', pageBuilder: (c, s) => _slide(s, HistoryPage(walletId: s.uri.queryParameters['wallet']))),
      GoRoute(path: '/wallets', pageBuilder: (c, s) => _slide(s, const WalletsPage())),
      GoRoute(path: '/budgets', pageBuilder: (c, s) => _slide(s, const BudgetsPage())),
      GoRoute(path: '/bills', pageBuilder: (c, s) => _slide(s, const BillsPage())),
      GoRoute(path: '/recurring', pageBuilder: (c, s) => _slide(s, const RecurringPage())),
      GoRoute(path: '/categories', pageBuilder: (c, s) => _slide(s, const CategoriesPage())),
      GoRoute(path: '/household', pageBuilder: (c, s) => _slide(s, const HouseholdPage())),
      GoRoute(path: '/goal/:id', pageBuilder: (c, s) => _slide(s, GoalDetailPage(id: s.pathParameters['id']!))),
    ],
  );
});

Page<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (c, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    );

/// Transisi "shared axis" horizontal: halaman baru bergeser sedikit + fade,
/// halaman lama mundur sedikit — terasa berlapis, bukan geser penuh.
Page<void> _slide(GoRouterState s, Widget child) => CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (c, a, sa, child) {
        final inCurve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        final outCurve = CurvedAnimation(parent: sa, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0), end: const Offset(-0.08, 0)).animate(outCurve),
          child: FadeTransition(
            opacity: inCurve,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(inCurve),
              child: child,
            ),
          ),
        );
      },
    );
