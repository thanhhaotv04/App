import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/app_colors.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  int _indexForLocation(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/history')) return 1;
    if (path.startsWith('/sync')) return 2;
    if (path.startsWith('/settings')) return 3;
    return 0;
  }

  void _navigate(BuildContext context, int index) {
    if (index == 1) return context.go('/history');
    if (index == 2) return context.go('/sync');
    if (index == 3) return context.go('/settings');
    context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFC47731),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.explore, size: 20, color: Color(0xFF1E1B16)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('VietNam Map Checkin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Travel log and check-in', style: TextStyle(fontSize: 11, color: colors.muted)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: AppTheme.toggleTheme,
            icon: ValueListenableBuilder<ThemeMode>(
              valueListenable: AppTheme.themeMode,
              builder: (context, mode, _) {
                return Icon(mode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined);
              },
            ),
            tooltip: 'Theme',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        height: 74,
        selectedIndex: _indexForLocation(context),
        onDestinationSelected: (value) => _navigate(context, value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.location_on_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), label: 'History'),
          NavigationDestination(icon: Icon(Icons.sync_alt_outlined), label: 'Sync'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
