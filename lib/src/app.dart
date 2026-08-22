import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  const MoneyManagerApp({super.key, this.now});

  static final themeMode = ValueNotifier(ThemeMode.light);

  /// Keeps visual previews deterministic without changing production time.
  final DateTime? now;

  @override
  State<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends State<MoneyManagerApp> {
  bool _loading = true;
  String? _userName;
  String? _password;

  @override
  void initState() {
    super.initState();
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final auth = await AuthCache.load();
    if (!mounted) return;
    setState(() {
      _userName = auth?.$1;
      _password = auth?.$2;
      _loading = false;
    });
  }

  Future<String?> _login(String user, String password) async {
    try {
      final baseUrl = await BackendConfig.loadUrl();
      final name = await AuthService(
        baseUrl: baseUrl,
      ).signIn(user.trim(), password);
      await AuthCache.save(name, password);
      if (mounted) {
        setState(() {
          _userName = name;
          _password = password;
        });
      }
      return null;
    } catch (error) {
      return error is AuthException
          ? error.message
          : 'Cannot reach backend. Start backend and check the URL.';
    }
  }

  Future<String?> _register(String user, String password) async {
    try {
      final baseUrl = await BackendConfig.loadUrl();
      final name = await AuthService(
        baseUrl: baseUrl,
      ).register(user.trim(), password);
      await AuthCache.save(name, password);
      if (mounted) {
        setState(() {
          _userName = name;
          _password = password;
        });
      }
      return null;
    } catch (error) {
      return error is AuthException
          ? error.message
          : 'Cannot reach backend. Start backend and check the URL.';
    }
  }

  Future<void> _logout() async {
    await AuthCache.clear();
    if (!mounted) return;
    setState(() {
      _userName = null;
      _password = null;
    });
  }

  Future<String?> _changePassword(
    String currentPassword,
    String newPassword,
    String confirmation,
  ) async {
    if (_password != currentPassword) return 'Current password is incorrect.';
    if (newPassword.length < 4) {
      return 'New password must be at least 4 characters.';
    }
    if (newPassword != confirmation) {
      return 'New password confirmation does not match.';
    }
    try {
      final baseUrl = await BackendConfig.loadUrl();
      await AuthService(baseUrl: baseUrl).updatePassword(
        name: _userName!,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      await AuthCache.save(_userName!, newPassword);
      if (mounted) setState(() => _password = newPassword);
      return null;
    } catch (error) {
      return error is AuthException
          ? error.message
          : 'Cannot update password on backend.';
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
        home: _loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _userName == null || _password == null
            ? AuthScreen(onLogin: _login, onRegister: _register)
            : HomeScreen(
                userName: _userName!,
                password: _password!,
                now: widget.now,
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

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });

  final AuthCallback onLogin;
  final AuthCallback onRegister;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _backend = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    BackendConfig.loadUrl().then((value) {
      if (mounted) _backend.text = value;
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _backend.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _password.text.length < 4) {
      setState(() => _error = 'Enter a username and a 4+ character password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await BackendConfig.saveUrl(_backend.text);
    final error = _registering
        ? await widget.onRegister(_user.text, _password.text)
        : await widget.onLogin(_user.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _resetPassword() async {
    if (_user.text.trim().isEmpty || _password.text.length < 4) {
      setState(
        () => _error =
            'Enter the username and new password, then reset password.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendConfig.saveUrl(_backend.text);
      final baseUrl = await BackendConfig.loadUrl();
      await AuthService(
        baseUrl: baseUrl,
      ).resetPassword(_user.text.trim(), _password.text);
      if (mounted) setState(() => _error = 'Password reset. Sign in now.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      _registering ? 'Create account' : 'Welcome back',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _registering
                          ? 'Create an account to sync your spending.'
                          : 'Sign in to continue managing your spending.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _user,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _backend,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        hintText: BackendConfig.defaultUrl,
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
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
                          : Text(_registering ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _registering = !_registering;
                                  _error = null;
                                }),
                          child: Text(
                            _registering
                                ? 'Already registered? Sign in'
                                : 'Create account',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Reset password'),
                        ),
                      ],
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
  const BrandAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(80);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      toolbarHeight: 80,
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
    required this.userName,
    required this.password,
    this.now,
    required this.onLogout,
    required this.onChangePassword,
  });

  final String userName;
  final String password;
  final DateTime? now;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = _store ?? await MoneyStore.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _transactions = store.transactions();
      _recurring = store.recurring();
    });
  }

  Future<void> _saveExpense(Tx tx, RecurringExpense? recurring) async {
    await _store!.addExpense(tx);
    if (recurring != null) await _store!.addRecurring(recurring);
    await _load();
    if (mounted) setState(() => _page = 0);
  }

  Future<void> _removeTransaction(Tx tx) async {
    await _store!.removeTransaction(tx.id);
    await _load();
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
    await _store!.addExpense(tx);
    await _load();
  }

  Future<void> _removeRecurring(RecurringExpense item) async {
    await _store!.removeRecurring(item.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        userName: widget.userName,
        password: widget.password,
        onReload: _load,
        onLogout: widget.onLogout,
        onChangePassword: widget.onChangePassword,
      ),
    ];
    return Scaffold(
      appBar: const BrandAppBar(),
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
                                    ? 'Every day • ${moneyFormat.format(item.amount)}'
                                    : 'Monthly on day ${item.dayOfMonth} • '
                                          '${moneyFormat.format(item.amount)}',
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
                  moneyFormat.format(balance),
                  style: TextStyle(
                    color: balance < 0 ? AppColors.danger : AppColors.ink,
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
                      value: moneyFormat.format(monthIncome),
                      icon: Icons.south_west_rounded,
                      color: AppColors.primary,
                    ),
                    CashFlowMetric(
                      label: 'Spent this month',
                      value: moneyFormat.format(monthExpenses),
                      icon: Icons.north_east_rounded,
                      color: AppColors.danger,
                    ),
                  ];
                  if (constraints.maxWidth < 350) {
                    return Column(
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
                '${moneyFormat.format(amounts[index])}',
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
                        moneyFormat.format(amounts[index]),
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
          moneyFormat.format(item.amount),
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
                '${income ? '+' : '-'} ${moneyFormat.format(tx.amount)}',
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
    if (_amount <= 0) return;
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
    await widget.onSave(tx, rule);
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
                            (net >= 0 ? '+' : '-') +
                                moneyFormat.format(net.abs()),
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
    required this.userName,
    required this.password,
    required this.onReload,
    required this.onLogout,
    required this.onChangePassword,
  });

  final MoneyStore store;
  final List<Tx> transactions;
  final List<RecurringExpense> recurring;
  final String userName;
  final String password;
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

  @override
  void initState() {
    super.initState();
    BackendConfig.loadUrl().then((value) {
      if (mounted) _backend.text = value;
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

  Future<void> _saveBackendUrl() async {
    await BackendConfig.saveUrl(_backend.text);
    _toast('Backend URL saved');
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      await BackendConfig.saveUrl(_backend.text);
      final baseUrl = await BackendConfig.loadUrl();
      final data = await MoneySyncService(
        baseUrl: baseUrl,
        userName: widget.userName,
        password: widget.password,
      ).syncTwoWay(widget.transactions, widget.recurring);
      await widget.store.replaceAll(data);
      await widget.onReload();
      _toast('Synced ${data.transactions.length} transactions');
    } catch (error) {
      _toast('Sync failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAndInstallUpdate() async {
    if (kIsWeb) {
      _toast('APK updates are available in the Android app.');
      return;
    }
    setState(() => _busy = true);
    try {
      final baseUrl = await BackendConfig.loadUrl();
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
      _toast('Update failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
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
    if (shouldClear == true) await onConfirm();
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

  @override
  Widget build(BuildContext context) {
    final dark = MoneyManagerApp.themeMode.value == ThemeMode.dark;
    return PageList(
      children: [
        const PageTitle('Account'),
        const SizedBox(height: 22),
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
                child: Text(
                  widget.userName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
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
              const Text(
                'Current 1.0.8+9',
                style: TextStyle(
                  color: AppColors.muted,
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
                decoration: const InputDecoration(hintText: 'Current password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPassword,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'New password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
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
                'Reset local data',
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
                            'this device.',
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
                            'from this device.',
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
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign Out'),
        ),
        if (_busy) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}
