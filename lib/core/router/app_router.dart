// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:peckish/features/about/presentation/about_screen.dart';
import 'package:peckish/features/settings/presentation/settings_screen.dart';
import 'package:peckish/features/today/presentation/today_screen.dart';

part 'app_router.g.dart';

CustomTransitionPage<T> _fade<T>({required LocalKey key, required Widget child}) =>
    CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (_, a, __, c) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: c),
    );

/// Route table. Deliberately NO onboarding gate: Peckish opens straight onto
/// Today — zero-friction is the product law (the daily loop costs at most two
/// taps), and any first-run guidance is an inline invitation, never a wall.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (c, s) => _fade(key: s.pageKey, child: const TodayScreen()),
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
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}
