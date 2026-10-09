import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services.dart';
import 'storage.dart';

final moneyFormat = NumberFormat.currency(
  locale: 'en_US',
  symbol: 'VND ',
  decimalDigits: 0,
);
final dateFormat = DateFormat('MMM d, HH:mm', 'en_US');
final fullDateFormat = DateFormat('EEEE, MMMM d, y', 'en_US');

String moneyText(num amount) =>
    MoneyManagerApp.hideAmounts.value ? '••••••' : moneyFormat.format(amount);

abstract final class AppColors {
  static const primary = Color(0xFF2E7D32);
  static const primarySoft = Color(0xFFDDF5D8);
  static const background = Color(0xFFF3FFF2);
  static const header = Color(0xFFEAF3E3);
  static const field = Color(0xFFEDF5E7);
  static const hero = Color(0xFFD5F3D1);
  static const heroBorder = Color(0xFFA1DE8C);
  static const ink = Color(0xFF0B2A16);
  static const muted = Color(0xFF65796A);
  static const danger = Color(0xFFB3261E);
}

class MoneyManagerApp extends StatefulWidget {
  const MoneyManagerApp({
    super.key,
    this.now,
    this.previewVersionName,
    this.previewVersionCode,
  });

  static final themeMode = ValueNotifier(ThemeMode.light);
  static final hideAmounts = ValueNotifier(false);
  static const hideAmountsKey = 'money-manager-hide-amounts';

  /// Keeps visual previews deterministic without changing production time.
  final DateTime? now;

  /// Keeps version text deterministic in visual previews.
  final String? previewVersionName;
  final int? previewVersionCode;

  @override
  State<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends State<MoneyManagerApp>
    with WidgetsBindingObserver {
  bool _loading = true;
  AuthSession? _session;
  String? _loadError;
  bool _retryingLogouts = false;
  int _pendingLogoutsCount = 0;
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAuth();
    } else {
      setState(() => _obscured = true);
    }
  }

  Future<void> _retryLogouts() async {
    if (_retryingLogouts) return;
    _retryingLogouts = true;
    try {
      final pending = await AuthCache.pendingLogouts();
      if (mounted) setState(() => _pendingLogoutsCount = pending.length);
      if (pending.isEmpty) return;
      final remaining = await AuthService.retryPendingLogouts();
      if (mounted) setState(() => _pendingLogoutsCount = remaining);
    } catch (_) {
      // Keep the queued revocation for the next app launch.
    } finally {
      _retryingLogouts = false;
    }
  }

  Future<void> _loadAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      MoneyManagerApp.hideAmounts.value =
          prefs.getBool(MoneyManagerApp.hideAmountsKey) ?? false;
      final session = await AuthCache.load();
      if (mounted) {
        setState(() {
          _session = session?.id.isNotEmpty == true ? session : null;
          _loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _session = null;
          _loadError = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          if (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) {
            _obscured = false;
          }
        });
      }
    }
    unawaited(_retryLogouts());
  }

  Future<String?> _authenticate(
    String user,
    String password, {
    required bool register,
  }) async {
    try {
      final session = register
          ? await AuthCache.registerOffline(user, password)
          : await AuthCache.signInOffline(user, password);
      if (mounted) setState(() => _session = session);
      return null;
    } catch (error) {
      return error is FormatException
          ? error.message
          : 'Could not access local storage in this browser. Check browser privacy settings and try again.';
    }
  }

  Future<String?> _login(String user, String password) =>
      _authenticate(user, password, register: false);

  Future<String?> _register(String user, String password) =>
      _authenticate(user, password, register: true);

  Future<String?> _authenticateOnline(
    String user,
    String password, {
    required bool register,
  }) async {
    try {
      final service = AuthService(baseUrl: await BackendConfig.loadUrl());
      final session = register
          ? await service.register(user, password)
          : await service.signIn(user, password);
      await AuthCache.save(session);
      if (mounted) setState(() => _session = session);
      return null;
    } catch (error) {
      return friendlyError(error);
    }
  }

  Future<String?> _resetPassword(
    String user,
    String password,
    String code,
  ) async {
    try {
      await AuthService(
        baseUrl: await BackendConfig.loadUrl(),
      ).resetPassword(user, password, code);
      return null;
    } catch (error) {
      return friendlyError(error);
    }
  }

  Future<void> _logout() async {
    final session = _session;
    if (session == null) return;
    try {
      await AuthCache.signOutLocally(session);
      await _loadAuth();
    } catch (error) {
      if (mounted) setState(() => _loadError = friendlyError(error));
    }
  }

  Future<String?> _changePassword(
    String currentPassword,
    String newPassword,
    String confirmation,
  ) async {
    if (newPassword.length < 12 || newPassword.length > 128) {
      return 'New password must have 12–128 characters.';
    }
    if (newPassword != confirmation) {
      return 'New password confirmation does not match.';
    }
    try {
      final previous = await AuthCache.requireCurrent(_session!);
      if (previous.isOffline) {
        await AuthCache.updateOfflinePassword(
          session: previous,
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
        return null;
      }
      final session = await AuthService(baseUrl: previous.backendUrl)
          .updatePassword(
            session: previous,
            currentPassword: currentPassword,
            newPassword: newPassword,
          );
      await AuthCache.saveIfCurrent(session, previous);
      if (mounted) setState(() => _session = session);
      return null;
    } catch (error) {
      return friendlyError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: MoneyManagerApp.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'money-manager',
        themeMode: themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        builder: (context, child) => Stack(
          children: [
            if (child != null)
              ExcludeSemantics(excluding: _obscured, child: child),
            if (_obscured)
              Positioned.fill(
                key: const ValueKey('privacy-cover'),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: const Center(
                    child: Icon(Icons.lock_outline, size: 48),
                  ),
                ),
              ),
          ],
        ),
        home: _loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _loadError != null
            ? Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      TextButton(
                        onPressed: _loadAuth,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _session == null
            ? AuthScreen(
                onLogin: _login,
                onRegister: _register,
                onServerLogin: (user, password) =>
                    _authenticateOnline(user, password, register: false),
                onServerRegister: (user, password) =>
                    _authenticateOnline(user, password, register: true),
                onResetPassword: _resetPassword,
                pendingLogouts: _pendingLogoutsCount,
                onRetryLogouts: _retryLogouts,
              )
            : HomeScreen(
                key: ValueKey(MoneyStore.scopeFor(_session!)),
                session: _session!,
                now: widget.now,
                versionName: widget.previewVersionName,
                versionCode: widget.previewVersionCode,
                onLogout: _logout,
                onChangePassword: _changePassword,
              ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      surface: dark ? const Color(0xFF172019) : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0E1610)
          : AppColors.background,
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: dark ? Colors.white : AppColors.ink,
        displayColor: dark ? Colors.white : AppColors.ink,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? const Color(0xFF172019) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF253028) : AppColors.field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(58),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(58),
          side: BorderSide(
            color: dark ? Colors.white54 : AppColors.muted,
            width: 1.5,
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        elevation: 0,
        backgroundColor: dark ? const Color(0xFF172019) : Colors.white,
        indicatorColor: dark ? const Color(0xFF29432D) : AppColors.primarySoft,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: dark
                ? Colors.white
                : states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: dark
                ? Colors.white
                : states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
            size: 29,
          ),
        ),
      ),
    );
  }
}

typedef AuthCallback = Future<String?> Function(String user, String password);
typedef ChangePasswordCallback =
    Future<String?> Function(
      String currentPassword,
      String newPassword,
      String confirmation,
    );

enum LocalAuthMode { signIn, register, resetPassword }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
    this.onServerLogin,
    this.onServerRegister,
    this.onResetPassword,
    this.pendingLogouts = 0,
    this.onRetryLogouts,
  });

  final AuthCallback onLogin;
  final AuthCallback onRegister;
  final AuthCallback? onServerLogin;
  final AuthCallback? onServerRegister;
  final Future<String?> Function(String user, String password, String code)?
  onResetPassword;
  final int pendingLogouts;
  final VoidCallback? onRetryLogouts;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _recovery = TextEditingController();
  bool _online = false;
  LocalAuthMode _mode = LocalAuthMode.signIn;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  bool get _registering => _mode == LocalAuthMode.register;
  bool get _resetting => _mode == LocalAuthMode.resetPassword;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _confirmation.dispose();
    _recovery.dispose();
    super.dispose();
  }

  void _setMode(LocalAuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _password.clear();
      _confirmation.clear();
      _recovery.clear();
      _obscurePassword = true;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final user = _user.text.trim();
    if (user.isEmpty || user.length > 80) {
      setState(() => _error = 'Enter a user name of 1–80 characters.');
      return;
    }
    final password = _password.text;
    final minimum = _registering || _resetting ? 12 : 4;
    if (password.length < minimum || password.length > 128) {
      setState(() => _error = 'Use a password of $minimum–128 characters.');
      return;
    }
    if ((_registering || _resetting) && password != _confirmation.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final error = _resetting
          ? await widget.onResetPassword!(user, password, _recovery.text.trim())
          : _registering
          ? await (_online ? widget.onServerRegister! : widget.onRegister)(
              user,
              password,
            )
          : await (_online ? widget.onServerLogin! : widget.onLogin)(
              user,
              password,
            );
      if (!mounted) return;
      if (_resetting && error == null) {
        _setMode(LocalAuthMode.signIn);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset. Sign in with your new password.'),
          ),
        );
      }
      setState(() => _error = error);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serverSettings() async {
    final controller = TextEditingController(
      text: await BackendConfig.loadUrl(),
    );
    if (!mounted) {
      controller.dispose();
      return;
    }
    String? error;
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Sync server'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Server address',
              hintText: 'https://your-server:3002',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await BackendConfig.saveUrl(controller.text);
                  if (context.mounted) Navigator.pop(context);
                } catch (failure) {
                  if (context.mounted) {
                    update(() => error = friendlyError(failure));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _resetting
                          ? 'Reset password'
                          : _registering
                          ? 'Create account'
                          : 'Welcome back',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _online
                          ? 'Use your sync account to access data on your other devices.'
                          : _registering
                          ? 'Create an account stored only on this device.'
                          : 'Sign in without a server or Wi-Fi connection.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 24),
                    if (widget.pendingLogouts > 0) ...[
                      const Text(
                        'Signed out on this device. Reconnect to finish signing out on the server.',
                      ),
                      TextButton(
                        onPressed: _busy ? null : widget.onRetryLogouts,
                        child: const Text('Retry sign-out'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_resetting)
                      SegmentedButton<LocalAuthMode>(
                        segments: const [
                          ButtonSegment(
                            value: LocalAuthMode.signIn,
                            icon: Icon(Icons.login),
                            label: Text('Sign in'),
                          ),
                          ButtonSegment(
                            value: LocalAuthMode.register,
                            icon: Icon(Icons.person_add_alt_1),
                            label: Text('Register'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _busy
                            ? null
                            : (selection) => _setMode(selection.first),
                        showSelectedIcon: false,
                        expandedInsets: EdgeInsets.zero,
                      ),
                    if (_resetting)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _setMode(LocalAuthMode.signIn),
                        child: const Text('Back to sign in'),
                      ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _user,
                      enabled: !_busy,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscurePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: _registering || _resetting
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      textInputAction: _registering || _resetting
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: _registering || _resetting
                          ? null
                          : (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: _resetting ? 'New password' : 'Password',
                        helperText: _registering || _resetting
                            ? 'Use at least 12 characters.'
                            : null,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (_registering || _resetting) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmation,
                        enabled: !_busy,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                        ),
                      ),
                    ],
                    if (_resetting) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _recovery,
                        enabled: !_busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Recovery code',
                          helperText:
                              'Ask the server owner for a one-time code.',
                          helperMaxLines: 3,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _resetting
                                  ? 'Reset password'
                                  : _registering
                                  ? 'Create account'
                                  : 'Sign in',
                            ),
                    ),
                    if (_online) ...[
                      if (!_registering && !_resetting)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _setMode(LocalAuthMode.resetPassword),
                          child: const Text('Forgot password?'),
                        ),
                      TextButton.icon(
                        onPressed: _busy ? null : _serverSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Server settings'),
                      ),
                    ],
                    if (widget.onServerLogin != null &&
                        widget.onServerRegister != null &&
                        widget.onResetPassword != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() => _online = !_online);
                                _setMode(LocalAuthMode.signIn);
                              },
                        child: Text(
                          _online
                              ? 'Use a local account'
                              : 'Use a sync account',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAppBar({super.key, this.actions});

  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(80);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      toolbarHeight: 80,
      actions: actions,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: dark ? const Color(0xFF1A251C) : AppColors.header,
      titleSpacing: 24,
      title: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            color: AppColors.primary,
            size: 34,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'money-manager',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dark ? Colors.white : AppColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    this.now,
    this.versionName,
    this.versionCode,
    required this.onLogout,
    required this.onChangePassword,
  });

  final AuthSession session;
  final DateTime? now;
  final String? versionName;
  final int? versionCode;
  final VoidCallback onLogout;
  final ChangePasswordCallback onChangePassword;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MoneyStore? _store;
  List<Tx> _transactions = [];
  List<RecurringExpense> _recurring = [];
  int _page = 0;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    MoneyManagerApp.hideAmounts.addListener(_privacyChanged);
    _load();
  }

  void _privacyChanged() => setState(() {});

  @override
  void dispose() {
    MoneyManagerApp.hideAmounts.removeListener(_privacyChanged);
    super.dispose();
  }

  Future<void> _toggleAmounts() async {
    try {
      final hidden = !MoneyManagerApp.hideAmounts.value;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(MoneyManagerApp.hideAmountsKey, hidden)) {
        throw const FormatException(
          'Could not save the privacy setting. Try again.',
        );
      }
      MoneyManagerApp.hideAmounts.value = hidden;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  Future<void> _load() async {
    try {
      final store = _store ?? await MoneyStore.load(session: widget.session);
      await store.refresh();
      if (!mounted) return;
      setState(() {
        _store = store;
        _transactions = store.transactions();
        _recurring = store.recurring();
        _storageError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _storageError = friendlyError(error));
    }
  }

  Future<void> _saveExpense(Tx tx, RecurringExpense? recurring) async {
    await _store!.addEntry(tx, recurring);
    await _load();
    if (mounted) setState(() => _page = 0);
  }

  Future<void> _removeTransaction(Tx tx) async {
    try {
      await _store!.removeTransaction(tx.id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Transaction deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _restoreTransaction(tx),
          ),
        ),
      );
  }

  Future<void> _restoreTransaction(Tx tx) async {
    try {
      await _store!.restoreTransaction(tx);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  Future<void> _removeRecurring(RecurringExpense item) async {
    try {
      await _store!.removeRecurring(item.id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_store == null) {
      return Scaffold(
        body: Center(
          child: _storageError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_storageError!),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                      TextButton(
                        onPressed: widget.onLogout,
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    final pages = [
      OverviewPage(
        transactions: _transactions,
        recurring: _recurring,
        now: widget.now,
        onAdd: () => setState(() => _page = 1),
        onRemoveRecurring: _removeRecurring,
      ),
      AddExpensePage(now: widget.now, onSave: _saveExpense),
      HistoryPage(transactions: _transactions, onRemove: _removeTransaction),
      AccountPage(
        store: _store!,
        transactions: _transactions,
        recurring: _recurring,
        session: widget.session,
        versionName: widget.versionName,
        versionCode: widget.versionCode,
        onReload: _load,
        onLogout: widget.onLogout,
        onChangePassword: widget.onChangePassword,
      ),
    ];
    return Scaffold(
      appBar: BrandAppBar(
        actions: [
          IconButton(
            tooltip: MoneyManagerApp.hideAmounts.value
                ? 'Show amounts'
                : 'Hide amounts',
            onPressed: _toggleAmounts,
            icon: Icon(
              MoneyManagerApp.hideAmounts.value
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: IndexedStack(index: _page, children: pages),
        ),
      ),
      bottomNavigationBar: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: NavigationBar(
            selectedIndex: _page,
            onDestinationSelected: (value) => setState(() => _page = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Overview',
              ),
              NavigationDestination(
                icon: Icon(Icons.add_card_outlined),
                selectedIcon: Icon(Icons.add_card),
                label: 'Add',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Account',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PageList extends StatelessWidget {
  const PageList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: children,
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

enum OverviewFilter { all, expenses, income }

class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.transactions,
    required this.recurring,
    this.now,
    required this.onAdd,
    required this.onRemoveRecurring,
  });

  final List<Tx> transactions;
  final List<RecurringExpense> recurring;
  final DateTime? now;
  final VoidCallback onAdd;
  final ValueChanged<RecurringExpense> onRemoveRecurring;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  OverviewFilter _filter = OverviewFilter.all;

  List<Tx> get _filtered => widget.transactions.where((tx) {
    return switch (_filter) {
      OverviewFilter.all => true,
      OverviewFilter.expenses => tx.type == TxType.expense,
      OverviewFilter.income => tx.type == TxType.income,
    };
  }).toList();

  int _totalFor(Iterable<Tx> items, TxType type) => items
      .where((tx) => tx.type == type)
      .fold(0, (sum, tx) => sum + tx.amount);

  Future<void> _adjustRecurring() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scheduled expenses'),
        content: SizedBox(
          width: 430,
          child: widget.recurring.isEmpty
              ? const Text('No scheduled expenses yet.')
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Column(
                      children: widget.recurring
                          .map(
                            (item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(categoryByName(item.category).icon),
                              title: Text(item.title),
                              subtitle: Text(
                                item.frequency == RecurringFrequency.daily
                                    ? 'Every day • ${moneyText(item.amount)}'
                                    : 'Monthly on day ${item.dayOfMonth} • '
                                          '${moneyText(item.amount)}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Delete scheduled expense',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final shouldDelete = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Delete schedule?'),
                                      content: Text(
                                        '“${item.title}” will no longer be '
                                        'recorded automatically.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.danger,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (shouldDelete != true) return;
                                  widget.onRemoveRecurring(item);
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final thisMonth = widget.transactions.where(
      (tx) => tx.date.year == now.year && tx.date.month == now.month,
    );
    final monthIncome = _totalFor(thisMonth, TxType.income);
    final monthExpenses = _totalFor(thisMonth, TxType.expense);
    final balance =
        _totalFor(widget.transactions, TxType.income) -
        _totalFor(widget.transactions, TxType.expense);
    final recent = _filtered.take(4).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return PageList(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF203A25) : AppColors.hero,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.heroBorder, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PageTitle('Overview'),
                        SizedBox(height: 4),
                        Text(
                          'All recorded transactions',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF315A34) : Colors.white70,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              Text(
                'Available balance',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                alignment: Alignment.centerLeft,
                child: Text(
                  moneyText(balance),
                  style: TextStyle(
                    color: balance < 0
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: 46,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = [
                    CashFlowMetric(
                      label: 'Income this month',
                      value: moneyText(monthIncome),
                      icon: Icons.south_west_rounded,
                      color: AppColors.primary,
                    ),
                    CashFlowMetric(
                      label: 'Spent this month',
                      value: moneyText(monthExpenses),
                      icon: Icons.north_east_rounded,
                      color: AppColors.danger,
                    ),
                  ];
                  if (constraints.maxWidth < 260 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        metrics.first,
                        const SizedBox(height: 12),
                        metrics.last,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: metrics.first),
                      const SizedBox(width: 12),
                      Expanded(child: metrics.last),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              if (recent.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _filter == OverviewFilter.all
                          ? 'No transactions yet.'
                          : 'No matching transactions yet.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: widget.onAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add a transaction'),
                    ),
                  ],
                )
              else
                ...recent.map((tx) => TransactionRow(tx: tx)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Activity',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: OverviewFilter.values
                    .map(
                      (filter) => ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: ChoiceChip(
                          label: Text(switch (filter) {
                            OverviewFilter.all => 'All',
                            OverviewFilter.expenses => 'Expenses',
                            OverviewFilter.income => 'Income',
                          }),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Text(
                'Spending trend',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Last three months',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              SpendingTrend(transactions: widget.transactions, now: now),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scheduled expenses',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _adjustRecurring,
                    icon: const Icon(Icons.tune),
                    label: const Text('Manage'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.recurring.isEmpty)
                const Text(
                  'No scheduled expenses yet. Add one from the Add tab.',
                  style: TextStyle(color: AppColors.muted),
                )
              else
                ...widget.recurring
                    .take(2)
                    .map((item) => ScheduledExpenseRow(item: item)),
            ],
          ),
        ),
      ],
    );
  }
}

class CashFlowMetric extends StatelessWidget {
  const CashFlowMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpendingTrend extends StatelessWidget {
  const SpendingTrend({
    super.key,
    required this.transactions,
    required this.now,
  });

  final List<Tx> transactions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final months = List.generate(
      3,
      (index) => DateTime(now.year, now.month - (2 - index)),
    );
    final amounts = months
        .map(
          (month) => transactions
              .where(
                (tx) =>
                    tx.type == TxType.expense &&
                    tx.date.year == month.year &&
                    tx.date.month == month.month,
              )
              .fold(0, (sum, tx) => sum + tx.amount),
        )
        .toList();
    final maximum = amounts.fold<int>(
      1,
      (current, amount) => amount > current ? amount : current,
    );

    return Column(
      children: List.generate(
        months.length,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: index == months.length - 1 ? 0 : 12),
          child: Semantics(
            label:
                '${DateFormat.MMM('en_US').format(months[index])} spending '
                '${moneyText(amounts[index])}',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      DateFormat.MMM('en_US').format(months[index]),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: amounts[index] / maximum,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(999),
                      color: AppColors.primary,
                      backgroundColor: AppColors.primarySoft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 94,
                    child: FittedBox(
                      alignment: Alignment.centerRight,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        moneyText(amounts[index]),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScheduledExpenseRow extends StatelessWidget {
  const ScheduledExpenseRow({super.key, required this.item});

  final RecurringExpense item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          categoryByName(item.category).icon,
          color: AppColors.primary,
          size: 28,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                item.frequency == RecurringFrequency.daily
                    ? 'Every day'
                    : 'Monthly on day ${item.dayOfMonth}',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        Text(
          moneyText(item.amount),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.tx, this.onDelete});

  final Tx tx;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final category = categoryByName(tx.category);
    final income = tx.type == TxType.income;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: category.color,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(category.icon, color: AppColors.ink, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${tx.note.isEmpty ? tx.category : tx.note} - '
                  '${dateFormat.format(tx.date)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${income ? '+' : '-'} ${moneyText(tx.amount)}',
                style: TextStyle(
                  color: income ? AppColors.primary : AppColors.danger,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete transaction',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
    );
  }
}

typedef SaveExpenseCallback =
    Future<void> Function(Tx tx, RecurringExpense? recurring);

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key, this.now, required this.onSave});

  final DateTime? now;
  final SaveExpenseCallback onSave;

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _note = TextEditingController();
  MoneyCategory _category = moneyCategories.first;
  TxType _type = TxType.expense;
  RecurringFrequency? _recurrence;
  String _digits = '';
  bool _busy = false;

  int get _amount => int.tryParse(_digits) ?? 0;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _key(String value) {
    setState(() {
      if (value == 'backspace') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
        return;
      }
      if (_digits.length >= 12) return;
      _digits = '$_digits$value'.replaceFirst(RegExp(r'^0+'), '');
    });
  }

  void _selectType(TxType type) {
    setState(() {
      _type = type;
      _recurrence = type == TxType.expense ? _recurrence : null;
      _category = type == TxType.income
          ? categoryByName('Income')
          : _category.name == 'Income'
          ? moneyCategories.first
          : _category;
    });
  }

  Future<void> _save() async {
    if (_busy || _amount <= 0) return;
    if (_note.text.trim().length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep the note under 500 characters.')),
      );
      return;
    }
    setState(() => _busy = true);
    final now = widget.now ?? DateTime.now();
    const uuid = Uuid();
    final title = _note.text.trim().isEmpty
        ? _category.name
        : _note.text.trim();
    final tx = Tx(
      id: uuid.v4(),
      title: title,
      note: _note.text.trim(),
      category: _category.name,
      amount: _amount,
      date: now,
      type: _type,
      icon: _category.icon.codePoint,
    );
    RecurringExpense? rule;
    if (_type == TxType.expense && _recurrence != null) {
      rule = RecurringExpense(
        id: uuid.v4(),
        title: title,
        amount: _amount,
        category: _category.name,
        frequency: _recurrence!,
        dayOfMonth: now.day,
        lastAppliedAt: now,
      );
    }
    try {
      await widget.onSave(tx, rule);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
      return;
    }
    if (!mounted) return;
    _note.clear();
    if (mounted) {
      setState(() {
        _digits = '';
        _category = moneyCategories.first;
        _type = TxType.expense;
        _recurrence = null;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _type == TxType.income
        ? [categoryByName('Income')]
        : moneyCategories
              .where(
                (item) =>
                    item.name != 'Income' &&
                    item.name != 'Daily' &&
                    item.name != 'Monthly',
              )
              .toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PageList(
      children: [
        SectionCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: SegmentedButton<TxType>(
                  segments: const [
                    ButtonSegment(
                      value: TxType.expense,
                      icon: Icon(Icons.north_east_rounded),
                      label: Text('Expense'),
                    ),
                    ButtonSegment(
                      value: TxType.income,
                      icon: Icon(Icons.south_west_rounded),
                      label: Text('Income'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) _selectType(selection.first);
                  },
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                height: 170,
                padding: const EdgeInsets.all(22),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF203A25) : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.heroBorder, width: 1.5),
                ),
                child: Semantics(
                  label: 'Amount ${moneyFormat.format(_amount)}',
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        moneyFormat.format(_amount),
                        style: const TextStyle(
                          fontSize: 54,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2,
                children:
                    const [
                          '1',
                          '2',
                          '3',
                          '4',
                          '5',
                          '6',
                          '7',
                          '8',
                          '9',
                          '000',
                          '0',
                          'backspace',
                        ]
                        .map(
                          (value) => FilledButton(
                            onPressed: () => _key(value),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(44, 52),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: value == 'backspace'
                                ? const Icon(
                                    Icons.backspace_outlined,
                                    semanticLabel: 'Delete last digit',
                                  )
                                : Text(
                                    value,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _amount > 0 && !_busy ? _save : null,
                icon: const Icon(Icons.check),
                label: Text(
                  _busy
                      ? 'Saving...'
                      : _type == TxType.income
                      ? 'Save income'
                      : 'Save expense',
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Details (optional)',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Category: ${_category.name}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = _type == TxType.income
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories
                        .map(
                          (category) => SizedBox(
                            width: width,
                            height: 48,
                            child: FilterChip(
                              selected: category.name == _category.name,
                              showCheckmark: false,
                              avatar: Icon(
                                category.icon,
                                color: category.name == _category.name
                                    ? AppColors.ink
                                    : AppColors.primary,
                              ),
                              label: Text(
                                category.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              side: BorderSide(
                                color: category.name == _category.name
                                    ? Colors.transparent
                                    : AppColors.muted.withValues(alpha: .45),
                              ),
                              selectedColor: dark
                                  ? const Color(0xFF315A34)
                                  : const Color(0xFFDCECCB),
                              backgroundColor: Theme.of(context).cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              onSelected: (_) =>
                                  setState(() => _category = category),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              if (_type == TxType.expense) ...[
                const SizedBox(height: 20),
                Text(
                  'Repeat',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _RepeatChip(
                      label: 'No repeat',
                      selected: _recurrence == null,
                      onSelected: () => setState(() => _recurrence = null),
                    ),
                    _RepeatChip(
                      label: 'Every day',
                      selected: _recurrence == RecurringFrequency.daily,
                      onSelected: () => setState(
                        () => _recurrence = RecurringFrequency.daily,
                      ),
                    ),
                    _RepeatChip(
                      label: 'Every month',
                      selected: _recurrence == RecurringFrequency.monthly,
                      onSelected: () => setState(
                        () => _recurrence = RecurringFrequency.monthly,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RepeatChip extends StatelessWidget {
  const _RepeatChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.transactions,
    required this.onRemove,
  });

  final List<Tx> transactions;
  final ValueChanged<Tx> onRemove;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _query = '';
  OverviewFilter _typeFilter = OverviewFilter.all;

  Future<void> _confirmRemove(Tx tx) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          '“${tx.title}” will be removed from this device. '
          'You can undo it immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldRemove == true) widget.onRemove(tx);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final filtered = widget.transactions
        .where(
          (tx) =>
              (_typeFilter == OverviewFilter.all ||
                  (_typeFilter == OverviewFilter.expenses &&
                      tx.type == TxType.expense) ||
                  (_typeFilter == OverviewFilter.income &&
                      tx.type == TxType.income)) &&
              (tx.title.toLowerCase().contains(query) ||
                  tx.note.toLowerCase().contains(query) ||
                  tx.category.toLowerCase().contains(query)),
        )
        .toList();
    final byDay = <DateTime, List<Tx>>{};
    for (final tx in filtered) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      byDay.putIfAbsent(day, () => []).add(tx);
    }
    return PageList(
      children: [
        const PageTitle('History'),
        const SizedBox(height: 18),
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            hintText: 'Search transactions',
            prefixIcon: Icon(Icons.search, size: 30),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: OverviewFilter.values
              .map(
                (filter) => ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: ChoiceChip(
                    label: Text(switch (filter) {
                      OverviewFilter.all => 'All',
                      OverviewFilter.expenses => 'Expenses',
                      OverviewFilter.income => 'Income',
                    }),
                    selected: _typeFilter == filter,
                    onSelected: (_) => setState(() => _typeFilter = filter),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          SectionCard(
            child: Text(
              _typeFilter == OverviewFilter.all && query.isEmpty
                  ? 'No transactions yet.'
                  : 'No matching transactions.',
              style: const TextStyle(color: AppColors.muted),
            ),
          )
        else
          ...byDay.entries.map((entry) {
            final income = entry.value
                .where((tx) => tx.type == TxType.income)
                .fold(0, (sum, tx) => sum + tx.amount);
            final expenses = entry.value
                .where((tx) => tx.type == TxType.expense)
                .fold(0, (sum, tx) => sum + tx.amount);
            final net = income - expenses;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat(
                                'EEEE, MMM d',
                                'en_US',
                              ).format(entry.key),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            (net >= 0 ? '+' : '-') + moneyText(net.abs()),
                            style: TextStyle(
                              color: net >= 0
                                  ? AppColors.primary
                                  : AppColors.danger,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...entry.value.asMap().entries.expand(
                      (item) => [
                        TransactionRow(
                          tx: item.value,
                          onDelete: () => _confirmRemove(item.value),
                        ),
                        if (item.key != entry.value.length - 1)
                          const Divider(height: 1),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.store,
    required this.transactions,
    required this.recurring,
    required this.session,
    this.versionName,
    this.versionCode,
    required this.onReload,
    required this.onLogout,
    required this.onChangePassword,
  });

  final MoneyStore store;
  final List<Tx> transactions;
  final List<RecurringExpense> recurring;
  final AuthSession session;
  final String? versionName;
  final int? versionCode;
  final Future<void> Function() onReload;
  final VoidCallback onLogout;
  final ChangePasswordCallback onChangePassword;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _backend = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _busy = false;
  bool _hasRecoveryData = false;

  @override
  void initState() {
    super.initState();
    _backend.text = widget.session.isOffline
        ? BackendConfig.defaultUrl
        : widget.session.backendUrl;
    widget.store
        .hasRecoveryData()
        .then((value) {
          if (mounted) setState(() => _hasRecoveryData = value);
        })
        .catchError((Object error) {
          _toast(friendlyError(error));
        });
  }

  @override
  void dispose() {
    _backend.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<AuthSession> _activeSession() async {
    final current = await AuthCache.requireCurrent(widget.session);
    final normalized = BackendConfig.normalize(_backend.text);
    final next = AuthSession(
      name: current.name,
      id: current.id,
      token: current.token,
      backendUrl: normalized,
    );
    if (MoneyStore.scopeFor(next) != widget.store.scope) {
      throw const FormatException(
        'To use another server, sign out first. Your data will stay with this account.',
      );
    }
    await BackendConfig.saveUrl(normalized);
    return next;
  }

  Future<void> _saveBackendUrl() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _activeSession();
      _toast('Server address saved');
    } catch (error) {
      _toast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = await _activeSession();
      await widget.store.refresh();
      final data = await MoneySyncService(
        session: session,
      ).syncTwoWay(widget.store.snapshot);
      await AuthCache.requireCurrent(session);
      await widget.store.replaceAll(data);
      await widget.onReload();
      _toast('Synced ${widget.store.transactions().length} transactions');
    } catch (error) {
      _toast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAndInstallUpdate() async {
    if (_busy) return;
    if (kIsWeb) {
      _toast('APK updates are available in the Android app.');
      return;
    }
    setState(() => _busy = true);
    try {
      final baseUrl = widget.session.isOffline
          ? await BackendConfig.loadUrl()
          : (await _activeSession()).backendUrl;
      final service = AppUpdateService(baseUrl: baseUrl);
      final info = await service.checkLatest();
      if (!info.available) {
        _toast(
          'Already up to date: ${AppUpdateService.currentVersionName}+'
          '${AppUpdateService.currentVersionCode}',
        );
        return;
      }
      if (!mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Install ${info.versionName}+${info.versionCode}?'),
          content: Text(
            info.notes.isEmpty ? 'A newer APK is available.' : info.notes,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Install'),
            ),
          ],
        ),
      );
      if (install != true) return;
      final path = await service.downloadApk(info);
      await service.installApk(path);
    } catch (error) {
      _toast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await widget.onChangePassword(
      _currentPassword.text,
      _newPassword.text,
      _confirmPassword.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
    }
    _toast(error ?? 'Password updated');
  }

  Future<void> _confirmClear({
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (shouldClear != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await onConfirm();
    } catch (error) {
      _toast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearThisMonth() async {
    final now = DateTime.now();
    final count = await widget.store.removeTransactionsWhere(
      (tx) => tx.date.year == now.year && tx.date.month == now.month,
    );
    await widget.onReload();
    _toast(
      count == 0 ? 'No transactions to delete' : 'Deleted $count transactions',
    );
  }

  Future<void> _clearToday() async {
    final now = DateTime.now();
    final count = await widget.store.removeTransactionsWhere(
      (tx) =>
          tx.date.year == now.year &&
          tx.date.month == now.month &&
          tx.date.day == now.day,
    );
    await widget.onReload();
    _toast(
      count == 0 ? 'No transactions to delete' : 'Deleted $count transactions',
    );
  }

  Future<void> _recoverData() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recover older data?'),
        content: Text(
          'Older versions may have mixed data from different people. Continue only if you own or are authorized to recover this device’s older data. You will select which records belong to ${widget.session.name}. The original copy will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I am authorized'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _activeSession();
      final data = await widget.store.readRecoveryData(confirmed: true);
      if (!mounted) return;
      final txIds = <String>{};
      final ruleIds = <String>{};
      final selected = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Recover into ${widget.session.name}'),
            content: SizedBox(
              width: 480,
              height: 360,
              child: Column(
                children: [
                  const Text(
                    'Select only your records. Recovered schedules will be paused to avoid unexpected charges.',
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount:
                          data.transactions.length + data.recurring.length,
                      itemBuilder: (context, index) {
                        final isTx = index < data.transactions.length;
                        final tx = isTx ? data.transactions[index] : null;
                        final rule = isTx
                            ? null
                            : data.recurring[index - data.transactions.length];
                        final id = tx?.id ?? rule!.id;
                        final ids = isTx ? txIds : ruleIds;
                        return CheckboxListTile(
                          title: Text(tx?.title ?? rule!.title),
                          subtitle: Text(
                            '${moneyText(tx?.amount ?? rule!.amount)} · ${isTx ? dateFormat.format(tx!.date) : 'Schedule (paused)'}',
                          ),
                          value: ids.contains(id),
                          onChanged: (value) => update(
                            () => value == true ? ids.add(id) : ids.remove(id),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: txIds.isEmpty && ruleIds.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Recover selected'),
              ),
            ],
          ),
        ),
      );
      if (selected != true) return;
      await _activeSession();
      await widget.store.replaceAll(
        MoneySyncData(
          data.transactions.where((tx) => txIds.contains(tx.id)).toList(),
          data.recurring
              .where((rule) => ruleIds.contains(rule.id))
              .map((rule) => rule.copyWith(active: false))
              .toList(),
        ),
      );
      await widget.onReload();
      _toast('Selected records recovered. The original copy was preserved.');
    } catch (error) {
      _toast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = MoneyManagerApp.themeMode.value == ThemeMode.dark;
    final offline = widget.session.isOffline;
    return PageList(
      children: [
        const PageTitle('Account'),
        const SizedBox(height: 22),
        if (_hasRecoveryData) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'An older copy is preserved on this device. Recover only records that belong to you.',
                ),
                TextButton(
                  onPressed: _busy ? null : _recoverData,
                  child: const Text('Recover older data'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        SectionCard(
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF315A34) : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.person_outline, size: 34),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (offline)
                      const Text(
                        'Stored on this device',
                        style: TextStyle(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: dark,
            onChanged: (value) {
              MoneyManagerApp.themeMode.value = value
                  ? ThemeMode.dark
                  : ThemeMode.light;
              setState(() {});
            },
            secondary: Icon(
              dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 32,
            ),
            title: const Text(
              'Dark mode',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        if (!offline) ...[
          const SizedBox(height: 20),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sync data',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _backend,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _saveBackendUrl,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save URL'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _syncNow,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'App updates',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _checkAndInstallUpdate,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Check for update'),
              ),
              const SizedBox(height: 12),
              Text(
                'Current ${widget.versionName ?? AppUpdateService.currentVersionName}+'
                '${widget.versionCode ?? AppUpdateService.currentVersionCode}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 16),
            title: const Text('Change password'),
            leading: const Icon(Icons.lock_outline),
            onExpansionChanged: (expanded) {
              if (!expanded) {
                _currentPassword.clear();
                _newPassword.clear();
                _confirmPassword.clear();
              }
            },
            children: [
              TextField(
                controller: _currentPassword,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: 'Current password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPassword,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'New password (12–128 characters)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'Confirm new password',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _changePassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Update Password'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 16),
            title: const Text('Delete transactions'),
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _confirmClear(
                        title: 'Clear today’s transactions?',
                        message:
                            'This removes every transaction dated today from '
                            'this account. ${offline ? 'The change stays on this device.' : 'The deletion will sync to your other devices.'}',
                        onConfirm: _clearToday,
                      ),
                icon: const Icon(Icons.today_outlined),
                label: const Text('Clear Today'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _confirmClear(
                        title: 'Clear this month’s transactions?',
                        message:
                            'This removes every transaction dated this month '
                            'from this account. ${offline ? 'The change stays on this device.' : 'The deletion will sync to your other devices.'}',
                        onConfirm: _clearThisMonth,
                      ),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Clear This Month'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _busy ? null : widget.onLogout,
          icon: Icon(offline ? Icons.switch_account_outlined : Icons.logout),
          label: Text(offline ? 'Switch account' : 'Sign Out'),
        ),
        if (_busy) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}
