import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'repositories/album_repository.dart';
import 'repositories/auth_service.dart';
import 'repositories/backend_config.dart';
import 'repositories/backup_service.dart';
import 'repositories/checkin_repository.dart';
import 'repositories/credential_store.dart';
import 'repositories/sync_service.dart';
import 'screens/auth_gate.dart';
import 'screens/album_screen.dart';
import 'screens/home_shell.dart';
import 'screens/insights_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_center_screen.dart';
import 'screens/timeline_screen.dart';
import 'theme/app_theme.dart';

class VietNamMapApp extends StatefulWidget {
  const VietNamMapApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<VietNamMapApp> createState() => _VietNamMapAppState();
}

class _VietNamMapAppState extends State<VietNamMapApp> {
  static const _userKey = CredentialStore.userKey;
  static const _sessionKey = 'vmc-auth-session';
  static const _credentials = CredentialStore();

  late final GoRouter _router = GoRouter(
    navigatorKey: VietNamMapApp.navigatorKey,
    initialLocation: '/checkin',
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/checkin',
            builder: (context, state) => const MapScreen(checkinOnly: true),
          ),
          GoRoute(
            path: '/album',
            builder: (context, state) => const AlbumScreen(),
          ),
          GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
          GoRoute(
            path: '/insights',
            builder: (context, state) => const InsightsScreen(),
          ),
          GoRoute(
            path: '/account',
            builder: (context, state) => SettingsScreen(onSignOut: _signOut),
          ),
          GoRoute(path: '/history', redirect: (context, state) => '/map'),
          GoRoute(
            path: '/sync',
            builder: (context, state) => const SyncCenterScreen(),
          ),
          GoRoute(
            path: '/timeline',
            builder: (context, state) => const TimelineScreen(),
          ),
          GoRoute(path: '/settings', redirect: (context, state) => '/account'),
        ],
      ),
    ],
  );

  bool _loading = true;
  bool _hasAccount = false;
  bool _authenticated = false;

  Future<void> _signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionKey, false);
    if (!mounted) return;
    _router.go('/checkin');
    setState(() => _authenticated = false);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(_userKey) ?? '';
    final hasAccount =
        user.isNotEmpty && await _credentials.hasOfflineAccount();
    if (!mounted) return;
    setState(() {
      _hasAccount = hasAccount;
      // Existing installs already have credentials but no session flag.
      _authenticated = hasAccount && (prefs.getBool(_sessionKey) ?? true);
      _loading = false;
    });
    if (hasAccount && (prefs.getBool(_sessionKey) ?? true)) {
      unawaited(_runAutoBackup(user));
    }
  }

  Future<void> _runAutoBackup(String userName) async {
    try {
      await const AutoBackupService().runIfDue(
        await CheckInRepository(userName: userName).load(),
        await AlbumRepository(userName: userName).load(),
      );
    } catch (_) {
      // Backup is best-effort and must not block opening the local app.
    }
  }

  Future<String?> _authenticate(
    AuthMode mode,
    String name,
    String password,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString(_userKey);
    final matchesLocal = await _credentials.matchesOffline(name, password);
    final backendUrl = await BackendConfig.loadUrl();
    final auth = AuthService(baseUrl: backendUrl);
    var accountName = name;
    var token = '';
    var backendVerified = false;
    if (mode == AuthMode.register) {
      try {
        final session = await auth.registerSession(name, password);
        accountName = session.name;
        token = session.token;
        backendVerified = true;
      } on AuthException catch (error) {
        return error.message;
      } on http.ClientException {
        return 'Connect to the backend to register a new account.';
      } on TimeoutException {
        return 'Connect to the backend to register a new account.';
      }
    } else {
      try {
        final session = await auth.loginSession(name, password);
        accountName = session.name;
        token = session.token;
        backendVerified = true;
      } on AuthException catch (error) {
        return error.message;
      } on http.ClientException {
        if (!matchesLocal) {
          return 'Cannot reach the backend. Connect to sign in or use this device’s saved account.';
        }
        accountName = storedUser!;
      } on TimeoutException {
        if (!matchesLocal) {
          return 'Cannot reach the backend. Connect to sign in or use this device’s saved account.';
        }
        accountName = storedUser!;
      }
    }

    if (backendVerified) {
      await _credentials.saveSession(
        userName: accountName,
        password: password,
        token: token,
      );
    } else {
      await prefs.setString(_userKey, accountName);
    }
    await _runAutoBackup(accountName);
    await prefs.setBool(_sessionKey, true);
    if (backendVerified) {
      try {
        final repo = CheckInRepository(userName: accountName);
        final synced = await SyncService(
          baseUrl: backendUrl,
          userName: accountName,
          token: token,
        ).syncTwoWay(await repo.load());
        await repo.save(synced);
        await AlbumRepository(
          userName: accountName,
        ).syncTwoWay(baseUrl: backendUrl);
      } catch (_) {
        // Keep local data usable; Account can retry sync after LAN recovery.
      }
    }
    if (mounted) {
      setState(() {
        _hasAccount = true;
        _authenticated = true;
      });
    }
    return null;
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
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (!_authenticated) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'VietNam Map Checkin',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: AuthScreen(hasAccount: _hasAccount, onSubmit: _authenticate),
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
