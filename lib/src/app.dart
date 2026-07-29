import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services.dart';
import 'storage.dart';

final moneyFormat = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);
final dateFormat = DateFormat('MMM d, HH:mm', 'en_US');

class MoneyManagerApp extends StatefulWidget {
  const MoneyManagerApp({super.key});

  static final themeMode = ValueNotifier(ThemeMode.system);

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
          : 'Cannot reach backend. Start backend on laptop and check the URL.';
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
                onLogout: _logout,
                onChangePassword: _changePassword,
              ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6A8F55),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF10140F)
          : const Color(0xFFF7FAF3),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1B211A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

typedef AuthCallback = Future<String?> Function(String user, String password);

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
      setState(
        () => _error =
            'Enter a username and a password with at least 4 characters.',
      );
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
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_user.text.trim().isEmpty || _password.text.length < 4) {
      setState(() => _error = 'Enter username and new password first.');
      return;
    }
    try {
      await BackendConfig.saveUrl(_backend.text);
      final url = await BackendConfig.loadUrl();
      await AuthService(
        baseUrl: url,
      ).resetPassword(_user.text.trim(), _password.text);
      if (mounted) {
        setState(() {
          _registering = false;
          _error = 'Password reset. Please sign in again.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.account_balance_wallet, size: 54),
                      const SizedBox(height: 12),
                      Text(
                        _registering
                            ? 'Create a shared local account'
                            : 'Sign in to continue',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Light, fast spending entry.',
                        textAlign: TextAlign.center,
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
                          hintText: 'http://192.168.1.10:3000',
                          prefixIcon: Icon(Icons.lan_outlined),
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
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_registering ? 'Register' : 'Sign in'),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
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
      ),
    );
  }
}

typedef ChangePasswordCallback =
    Future<String?> Function(
      String currentPassword,
      String newPassword,
      String confirmation,
    );

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.userName,
    required this.password,
    required this.onLogout,
    required this.onChangePassword,
  });

  final String userName;
  final String password;
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
        onRemoveRecurring: _removeRecurring,
      ),
      AddExpensePage(onSave: _saveExpense),
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
      appBar: AppBar(
        title: const Text('money-manager'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: IndexedStack(index: _page, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Add',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.transactions,
    required this.recurring,
    required this.onRemoveRecurring,
  });

  final List<Tx> transactions;
  final List<RecurringExpense> recurring;
  final ValueChanged<RecurringExpense> onRemoveRecurring;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = transactions.where(
      (tx) =>
          tx.date.year == now.year &&
          tx.date.month == now.month &&
          tx.date.day == now.day,
    );
    final month = transactions.where(
      (tx) => tx.date.year == now.year && tx.date.month == now.month,
    );
    int total(Iterable<Tx> items) => items.fold(
      0,
      (sum, tx) => sum + (tx.type == TxType.income ? -tx.amount : tx.amount),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Overview', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Today',
                value: moneyFormat.format(total(today)),
                icon: Icons.today,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'This month',
                value: moneyFormat.format(total(month)),
                icon: Icons.calendar_month,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Recent', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No expenses yet.'),
            ),
          )
        else
          ...transactions.take(5).map((tx) => TransactionTile(tx: tx)),
        const SizedBox(height: 20),
        Text(
          'Automatic expenses',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (recurring.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No daily or monthly rules yet.'),
            ),
          )
        else
          ...recurring.map(
            (item) => RecurringTile(
              item: item,
              onDelete: () => onRemoveRecurring(item),
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 18),
            Text(label),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(value, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, this.onDelete});

  final Tx tx;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final category = categoryByName(tx.category);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: category.color,
          child: Icon(category.icon, color: Colors.black87),
        ),
        title: Text(tx.title),
        subtitle: Text(
          '${tx.category} • ${dateFormat.format(tx.date)}'
          '${tx.note.isEmpty ? '' : '\n${tx.note}'}',
        ),
        isThreeLine: tx.note.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${tx.type == TxType.income ? '+' : '-'}'
              '${moneyFormat.format(tx.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: tx.type == TxType.income
                    ? Colors.green
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete transaction',
              ),
          ],
        ),
      ),
    );
  }
}

class RecurringTile extends StatelessWidget {
  const RecurringTile({super.key, required this.item, required this.onDelete});

  final RecurringExpense item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = item.frequency == RecurringFrequency.daily
        ? 'Every day at 00:00'
        : 'Every month on day ${item.dayOfMonth} at 00:00';
    return Card(
      child: ListTile(
        leading: Icon(categoryByName(item.category).icon),
        title: Text('${item.title} • ${moneyFormat.format(item.amount)}'),
        subtitle: Text(subtitle),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
        ),
      ),
    );
  }
}

typedef SaveExpenseCallback =
    Future<void> Function(Tx tx, RecurringExpense? recurring);

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key, required this.onSave});

  final SaveExpenseCallback onSave;

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _amount = TextEditingController();
  MoneyCategory _category = moneyCategories.first;
  TxType _type = TxType.expense;
  RecurringFrequency? _frequency;
  int _dayOfMonth = 1;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (_title.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title and amount.')),
      );
      return;
    }
    setState(() => _busy = true);
    final now = DateTime.now();
    const uuid = Uuid();
    final id = uuid.v4();
    final tx = Tx(
      id: id,
      title: _title.text.trim(),
      note: _note.text.trim(),
      category: _type == TxType.income ? 'Income' : _category.name,
      amount: amount,
      date: now,
      type: _type,
      icon: (_type == TxType.income ? Icons.savings : _category.icon).codePoint,
    );
    final rule = _frequency == null
        ? null
        : RecurringExpense(
            id: uuid.v4(),
            title: tx.title,
            amount: amount,
            category: tx.category,
            frequency: _frequency!,
            dayOfMonth: _dayOfMonth,
            lastAppliedAt: now,
          );
    await widget.onSave(tx, rule);
    _title.clear();
    _note.clear();
    _amount.clear();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Add expense', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        SegmentedButton<TxType>(
          segments: const [
            ButtonSegment(value: TxType.expense, label: Text('Expense')),
            ButtonSegment(value: TxType.income, label: Text('Income')),
          ],
          selected: {_type},
          onSelectionChanged: (value) => setState(() => _type = value.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
        if (_type == TxType.expense) ...[
          const SizedBox(height: 18),
          Text('Category', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: moneyCategories
                .where((item) => item.name != 'Income')
                .map(
                  (item) => ChoiceChip(
                    avatar: Icon(item.icon, size: 18),
                    label: Text(item.name),
                    selected: _category.name == item.name,
                    onSelected: (_) => setState(() => _category = item),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<RecurringFrequency?>(
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'Automatic expense'),
            items: const [
              DropdownMenuItem(value: null, child: Text('One time')),
              DropdownMenuItem(
                value: RecurringFrequency.daily,
                child: Text('Daily'),
              ),
              DropdownMenuItem(
                value: RecurringFrequency.monthly,
                child: Text('Monthly'),
              ),
            ],
            onChanged: (value) => setState(() => _frequency = value),
          ),
          if (_frequency == RecurringFrequency.monthly) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _dayOfMonth,
              decoration: const InputDecoration(labelText: 'Day of month'),
              items: List.generate(
                31,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1}'),
                ),
              ),
              onChanged: (value) => setState(() => _dayOfMonth = value ?? 1),
            ),
          ],
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_busy ? 'Saving...' : 'Save'),
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
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final query = _filter.toLowerCase();
    final filtered = widget.transactions
        .where(
          (tx) =>
              tx.title.toLowerCase().contains(query) ||
              tx.note.toLowerCase().contains(query) ||
              tx.category.toLowerCase().contains(query),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('History', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) => setState(() => _filter = value),
          decoration: const InputDecoration(
            labelText: 'Search',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        ...filtered.map(
          (tx) => TransactionTile(tx: tx, onDelete: () => widget.onRemove(tx)),
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
    super.dispose();
  }

  void _toast(String message) {
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
      if (install != true) {
        _toast('Update cancelled');
        return;
      }
      _toast('Downloading APK...');
      final path = await service.downloadApk(info);
      _toast('Opening Android installer...');
      await service.installApk(path);
    } catch (error) {
      _toast('Update failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (current.text, next.text, confirm.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (result == null) return;
    final error = await widget.onChangePassword(
      result.$1,
      result.$2,
      result.$3,
    );
    _toast(error ?? 'Password updated');
  }

  Future<void> _clearThisMonth() async {
    final now = DateTime.now();
    final count = await widget.store.removeTransactionsWhere(
      (tx) => tx.date.year == now.year && tx.date.month == now.month,
    );
    await widget.onReload();
    _toast(count == 0 ? 'No expenses to delete' : 'Deleted $count expenses');
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
    _toast(count == 0 ? 'No expenses to delete' : 'Deleted $count expenses');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Account', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(widget.userName),
            subtitle: Text('${widget.transactions.length} transactions'),
            trailing: IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _backend,
          decoration: InputDecoration(
            labelText: 'Backend URL',
            prefixIcon: const Icon(Icons.lan_outlined),
            suffixIcon: IconButton(
              onPressed: _saveBackendUrl,
              icon: const Icon(Icons.save_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: MoneyManagerApp.themeMode.value == ThemeMode.dark,
                onChanged: (dark) {
                  MoneyManagerApp.themeMode.value = dark
                      ? ThemeMode.dark
                      : ThemeMode.light;
                  setState(() {});
                },
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark mode'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync data'),
                onTap: _busy ? null : _syncNow,
              ),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('LAN update'),
                subtitle: const Text('Current 1.0.8+9'),
                onTap: _busy ? null : _checkAndInstallUpdate,
              ),
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Change password'),
                onTap: _changePassword,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('Delete today expenses'),
                onTap: _clearToday,
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Delete this month expenses'),
                onTap: _clearThisMonth,
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
