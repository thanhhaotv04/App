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
  static const primary = Color(0xFF78D26C);
  static const primarySoft = Color(0xFFDDF5D8);
  static const background = Color(0xFFF3FFF2);
  static const header = Color(0xFFEAF3E3);
  static const field = Color(0xFFEDF5E7);
  static const hero = Color(0xFFD5F3D1);
  static const heroBorder = Color(0xFFA1DE8C);
  static const ink = Color(0xFF203725);
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
  static const themeModeKey = 'money-manager-dark-mode';
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
      MoneyManagerApp.themeMode.value =
          prefs.getBool(MoneyManagerApp.themeModeKey) == true
          ? ThemeMode.dark
          : ThemeMode.light;
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
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
          surface: dark ? const Color(0xFF1D211E) : Colors.white,
        ).copyWith(
          onSurface: dark ? const Color(0xFFD7DFD8) : AppColors.ink,
          onSurfaceVariant: dark ? const Color(0xFFACB9AD) : AppColors.muted,
          surfaceContainer: dark ? const Color(0xFF252A26) : null,
          surfaceContainerHigh: dark ? const Color(0xFF2B302C) : null,
          surfaceContainerHighest: dark ? const Color(0xFF323833) : null,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF121512)
          : AppColors.background,
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF292F2A) : AppColors.field,
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
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(58),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(58),
          side: BorderSide(color: scheme.onSurfaceVariant, width: 1.5),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: dark ? const Color(0xFF334738) : AppColors.primarySoft,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: scheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: scheme.onSurface, size: 29),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      toolbarHeight: 56,
      actions: actions,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: dark ? const Color(0xFF222723) : AppColors.header,
      titleSpacing: 20,
      title: Row(
        children: [
          const Icon(Icons.eco_outlined, color: AppColors.primary, size: 26),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'money-manager',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
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
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
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
        padding: padding ?? const EdgeInsets.all(22),
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
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w900,
      ),
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

  int _total(Iterable<Tx> items) => _totalFor(
    items,
    _filter == OverviewFilter.income ? TxType.income : TxType.expense,
  );

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
    final filtered = _filtered;
    final today = filtered.where(
      (tx) =>
          tx.date.year == now.year &&
          tx.date.month == now.month &&
          tx.date.day == now.day,
    );
    final thisMonth = filtered.where(
      (tx) => tx.date.year == now.year && tx.date.month == now.month,
    );
    final thisYear = filtered.where((tx) => tx.date.year == now.year);
    final daily = widget.recurring
        .where((item) => item.frequency == RecurringFrequency.daily)
        .fold(0, (sum, item) => sum + item.amount);
    final monthly = widget.recurring
        .where((item) => item.frequency == RecurringFrequency.monthly)
        .fold(0, (sum, item) => sum + item.amount);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return PageList(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF252D26) : AppColors.hero,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: dark ? const Color(0xFF405744) : AppColors.heroBorder,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PageTitle('Overview'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 165,
                    child: DropdownButtonFormField<OverviewFilter>(
                      initialValue: _filter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Filter',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                      ),
                      items: OverviewFilter.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                switch (value) {
                                  OverviewFilter.all => 'All',
                                  OverviewFilter.expenses => 'Expenses',
                                  OverviewFilter.income => 'Income',
                                },
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _filter = value ?? _filter),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                fullDateFormat.format(now),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              FittedBox(
                alignment: Alignment.centerLeft,
                child: Text(
                  moneyText(_total(thisYear)),
                  style: const TextStyle(
                    fontSize: 48,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Today',
                      value: moneyText(_total(today)),
                      icon: Icons.today_outlined,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: StatCard(
                      label: 'This month',
                      value: moneyText(_total(thisMonth)),
                      icon: Icons.calendar_month_outlined,
                    ),
                  ),
                ],
              ),
              if (widget.transactions.isEmpty) ...[
                const SizedBox(height: 20),
                const Text('No transactions yet.'),
                TextButton.icon(
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add a transaction'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'By month',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 12,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent:
                        MediaQuery.textScalerOf(context).scale(16) > 22
                        ? 230
                        : null,
                    childAspectRatio: constraints.maxWidth < 330 ? 1.15 : 1.58,
                  ),
                  itemBuilder: (context, index) {
                    final monthNumber = index + 1;
                    final amount = _total(
                      filtered.where(
                        (tx) =>
                            tx.date.year == now.year &&
                            tx.date.month == monthNumber,
                      ),
                    );
                    final selected = monthNumber == now.month;
                    return Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        color: selected
                            ? (dark
                                  ? const Color(0xFF354A38)
                                  : const Color(0xFFC1EAAF))
                            : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(22),
                        border: selected
                            ? Border.all(color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat.MMMM(
                              'en_US',
                            ).format(DateTime(now.year, monthNumber)),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          FittedBox(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              moneyText(amount),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Automatic expenses',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _adjustRecurring,
                    icon: const Icon(Icons.tune),
                    label: const Text('Adjust'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AutomaticRow(
                icon: Icons.calendar_month_outlined,
                label: 'Monthly expense',
                amount: monthly,
              ),
              const SizedBox(height: 12),
              AutomaticRow(
                icon: Icons.today_outlined,
                label: 'Daily expense',
                amount: daily,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
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
              if (widget.transactions.isEmpty)
                Text(
                  'No transactions yet.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...widget.transactions
                    .take(4)
                    .map((tx) => TransactionRow(tx: tx)),
            ],
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 28),
          const SizedBox(height: 15),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class AutomaticRow extends StatelessWidget {
  const AutomaticRow({
    super.key,
    required this.icon,
    required this.label,
    required this.amount,
  });

  final IconData icon;
  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          moneyText(amount),
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
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
                  color: income
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.error,
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
        : moneyCategories.where((item) => item.name != 'Income').toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PageList(
      children: [
        SectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 130,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF252D26) : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF405744)
                        : AppColors.heroBorder,
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
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
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: TextButton(
                        onPressed: () => _selectType(
                          _type == TxType.expense
                              ? TxType.income
                              : TxType.expense,
                        ),
                        child: Text(
                          _type == TxType.expense ? 'Income' : 'Expense',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories
                    .map(
                      (category) => FilterChip(
                        selected: category.name == _category.name,
                        showCheckmark: false,
                        avatar: Icon(
                          category.icon,
                          color: category.name == _category.name
                              ? (dark
                                    ? Theme.of(context).colorScheme.onSurface
                                    : AppColors.ink)
                              : AppColors.primary,
                        ),
                        label: Text(category.name),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                        side: BorderSide(
                          color: category.name == _category.name
                              ? Colors.transparent
                              : Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: .45),
                        ),
                        selectedColor: dark
                            ? const Color(0xFF354A38)
                            : const Color(0xFFDCECCB),
                        backgroundColor: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: (_) => setState(() {
                          _category = category;
                          _recurrence = switch (category.name) {
                            'Daily' => RecurringFrequency.daily,
                            'Monthly' => RecurringFrequency.monthly,
                            _ => null,
                          };
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  hintText: 'Note',
                  prefixIcon: Icon(Icons.notes),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 8,
                childAspectRatio: 2.2,
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
                          (value) => Semantics(
                            button: true,
                            label: value == 'backspace'
                                ? 'Delete last digit'
                                : value,
                            child: FilledButton(
                              onPressed: () => _key(value),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(44, 52),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: value == 'backspace'
                                  ? const Icon(Icons.backspace_outlined)
                                  : Text(
                                      value,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 10),
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
            ],
          ),
        ),
      ],
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
    return PageList(
      children: [
        const PageTitle('History'),
        const SizedBox(height: 22),
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            hintText: 'Search transactions',
            prefixIcon: Icon(Icons.search, size: 30),
          ),
        ),
        if (widget.transactions.any((tx) => tx.type == TxType.income)) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: OverviewFilter.values
                .map(
                  (filter) => ChoiceChip(
                    label: Text(switch (filter) {
                      OverviewFilter.all => 'All',
                      OverviewFilter.expenses => 'Expenses',
                      OverviewFilter.income => 'Income',
                    }),
                    selected: _typeFilter == filter,
                    onSelected: (_) => setState(() => _typeFilter = filter),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          SectionCard(
            child: Text(
              'No matching transactions.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...filtered.map(
            (tx) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: TransactionRow(
                  tx: tx,
                  onDelete: () => _confirmRemove(tx),
                ),
              ),
            ),
          ),
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
                  color: dark ? const Color(0xFF354A38) : AppColors.primarySoft,
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
                      Text(
                        'Stored on this device',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
            onChanged: (value) async {
              try {
                final prefs = await SharedPreferences.getInstance();
                if (!await prefs.setBool(MoneyManagerApp.themeModeKey, value)) {
                  throw const FormatException('Could not save dark mode.');
                }
                MoneyManagerApp.themeMode.value = value
                    ? ThemeMode.dark
                    : ThemeMode.light;
                if (mounted) setState(() {});
              } catch (_) {
                _toast('Could not save dark mode. Try again.');
              }
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
                'LAN update',
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Change password',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reset spending data',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
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
