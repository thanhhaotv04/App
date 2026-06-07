import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth_gate.dart';
import 'screens/home_shell.dart';
import 'screens/history_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_screen.dart';
import 'theme/app_theme.dart';

class VietNamMapApp extends StatefulWidget {
  const VietNamMapApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<VietNamMapApp> createState() => _VietNamMapAppState();
}

class _VietNamMapAppState extends State<VietNamMapApp> {
  static const _userKey = 'vmc-auth-user';
  static const _passwordKey = 'vmc-auth-password';

  static final GoRouter _router = GoRouter(
    navigatorKey: VietNamMapApp.navigatorKey,
    initialLocation: '/map',
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/map',
            builder: (context, state) => const MapScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/sync',
            builder: (context, state) => const SyncScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );

  bool _loading = true;
  bool _hasAccount = false;
  bool _showPicker = false;
  bool _showApp = false;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(_userKey) ?? '';
    if (!mounted) return;
    setState(() {
      _userName = user;
      _hasAccount = user.isNotEmpty && (prefs.getString(_passwordKey) ?? '').isNotEmpty;
      _showPicker = _hasAccount;
      _loading = false;
    });
  }

  Future<String?> _login(String name, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString(_userKey);
    final storedPassword = prefs.getString(_passwordKey);
    if (storedUser == null || storedPassword == null) {
      await prefs.setString(_userKey, name);
      await prefs.setString(_passwordKey, password);
      if (mounted) {
        setState(() {
          _userName = name;
          _hasAccount = true;
          _showPicker = true;
        });
      }
      return null;
    }
    if (storedUser != name || storedPassword != password) {
      return 'Incorrect user name or password.';
    }
    if (mounted) {
      setState(() {
        _userName = name;
        _showPicker = true;
      });
    }
    return null;
  }

  void _logout() {
    setState(() {
      _showPicker = false;
      _showApp = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (context, mode, _) {
        if (_loading) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: const Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        if (!_showPicker) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'VietNam Map Checkin',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: AuthScreen(hasAccount: _hasAccount, onSubmit: _login),
          );
        }
        if (!_showApp) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'VietNam Map Checkin',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: AppPickerScreen(
              userName: _userName,
              onOpenApp: () => setState(() => _showApp = true),
              onLogout: _logout,
            ),
          );
        }
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'VietNam Map Checkin',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          routerConfig: _router,
        );
      },
    );
  }
}
