// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:peckish/features/about/presentation/about_screen.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/features/barcode/presentation/barcode_db_screen.dart';
import 'package:peckish/features/barcode/presentation/scan_screen.dart';
import 'package:peckish/features/food/presentation/foods_screen.dart';
import 'package:peckish/features/settings/presentation/privacy_screen.dart';
import 'package:peckish/features/settings/presentation/settings_screen.dart';
import 'package:peckish/features/sync/presentation/sync_screen.dart';

part 'app_router.g.dart';

CustomTransitionPage<T> _fade<T>({required LocalKey key, required Widget child}) =>
    CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (_, a, __, c) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: c),
    );

/// Four-tab shell. Deliberately NO onboarding gate: Peckish opens straight
/// onto Today — the daily loop costs at most two taps, and first-run guidance
/// is inline invitation, never a wall.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            _TabShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (c, s) =>
                _fade(key: s.pageKey, child: const TodayScreen()),
          ),
          GoRoute(
            path: '/plan',
            pageBuilder: (c, s) =>
                _fade(key: s.pageKey, child: const PlanScreen()),
          ),
          GoRoute(
            path: '/recipes',
            pageBuilder: (c, s) =>
                _fade(key: s.pageKey, child: const RecipesScreen()),
          ),
          GoRoute(
            path: '/groceries',
            pageBuilder: (c, s) =>
                _fade(key: s.pageKey, child: const GroceriesScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (c, s) =>
            _fade(key: s.pageKey, child: const SettingsScreen()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (c, s) =>
            _fade(key: s.pageKey, child: const AboutScreen()),
      ),
      GoRoute(
        path: '/scan',
        // ?day=YYYY-MM-DD when the scan was opened from a past day's +
        // sheet; absent means today, which is every other entry point.
        pageBuilder: (c, s) => _fade(
            key: s.pageKey,
            child: ScanScreen(day: s.uri.queryParameters['day'])),
      ),
      GoRoute(
        path: '/barcode-db',
        pageBuilder: (c, s) =>
            _fade(key: s.pageKey, child: const BarcodeDbScreen()),
      ),
      GoRoute(
        path: '/foods',
        pageBuilder: (c, s) =>
            _fade(key: s.pageKey, child: const FoodsScreen()),
      ),
      GoRoute(
        path: '/sync',
        pageBuilder: (c, s) =>
            _fade(key: s.pageKey, child: const SyncScreen()),
      ),
      GoRoute(
        path: '/privacy',
        pageBuilder: (c, s) =>
            _fade(key: s.pageKey, child: const PrivacyScreen()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (c, s) => _fade(key: s.pageKey, child: HistoryScreen()),
      ),
      GoRoute(
        path: '/history/:day',
        pageBuilder: (c, s) => _fade(
            key: s.pageKey,
            child: HistoryDayScreen(day: s.pathParameters['day']!)),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

class _TabShell extends StatelessWidget {
  const _TabShell({required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = ['/', '/plan', '/recipes', '/groceries'];

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexOf(location).clamp(0, 3);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined),
              selectedIcon: Icon(Icons.wb_sunny),
              label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Plan'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Recipes'),
          NavigationDestination(
              icon: Icon(Icons.shopping_basket_outlined),
              selectedIcon: Icon(Icons.shopping_basket),
              label: 'Groceries'),
        ],
      ),
    );
  }
}
