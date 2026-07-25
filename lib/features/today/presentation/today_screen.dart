import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Today — the home surface. The real screen (totals vs targets + one-tap
/// recents) lands with the diary feature; this shell exists so the scaffold
/// boots and routes.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peckish'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: const Center(child: Text('The table is being set.')),
    );
  }
}
