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
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(2),
              child: Image.asset(
                'assets/App_VietNamMap_Logo_no_background.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'VietNam Map Checkin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Travel log and check-in',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: AppTheme.toggleTheme,
            icon: ValueListenableBuilder<ThemeMode>(
              valueListenable: AppTheme.themeMode,
              builder: (context, mode, _) {
                return Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  size: 34,
                );
              },
            ),
            tooltip: 'Theme',
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexForLocation(context),
        onDestinationSelected: (value) => _navigate(context, value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_alt_outlined),
            label: 'Sync',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
