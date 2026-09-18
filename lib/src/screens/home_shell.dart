import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  int _indexForLocation(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/album')) return 1;
    if (path.startsWith('/map')) return 2;
    if (path.startsWith('/insights')) return 3;
    if (path.startsWith('/account')) return 4;
    return 0;
  }

  void _navigate(BuildContext context, int index) {
    if (index == 1) return context.go('/album');
    if (index == 2) return context.go('/map');
    if (index == 3) return context.go('/insights');
    if (index == 4) return context.go('/account');
    context.go('/checkin');
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
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexForLocation(context),
        onDestinationSelected: (value) => _navigate(context, value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            label: 'Checkin',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_album_outlined),
            label: 'Album',
          ),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
