import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services.dart';
import 'storage.dart';

final dateTitleFormat = DateFormat('EEE, dd/MM/yyyy');
final shortDateFormat = DateFormat('dd/MM/yyyy');

abstract final class AppColors {
  static const surface = Color(0xFFFCF9F4);
  static const primary = Color(0xFF5E5452);
  static const secondary = Color(0xFFD6E3F8);
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFF44336);
  static const container = Color(0xFFF6F3EE);
  static const primarySoft = Color(0xFFEEDDD9);
  static const background = surface;
  static const header = surface;
  static const field = container;
  static const hero = Color(0xFFF2ECE6);
  static const heroBorder = primary;
  static const ink = primary;
  static const muted = Color(0xFF807572);
  static const danger = error;
}

@immutable
class DoodlePalette extends ThemeExtension<DoodlePalette> {
  const DoodlePalette({
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.success,
    required this.error,
    required this.container,
    required this.border,
    required this.muted,
    required this.field,
    required this.soft,
    required this.glow,
    required this.onAccent,
  });

  final Color surface;
  final Color primary;
  final Color secondary;
  final Color success;
  final Color error;
  final Color container;
  final Color border;
  final Color muted;
  final Color field;
  final Color soft;
  final Color glow;
  final Color onAccent;

  static const light = DoodlePalette(
    surface: AppColors.surface,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    success: AppColors.success,
    error: AppColors.error,
    container: AppColors.container,
    border: AppColors.primary,
    muted: AppColors.muted,
    field: AppColors.field,
    soft: AppColors.primarySoft,
    glow: AppColors.secondary,
    onAccent: AppColors.ink,
  );

  static const dark = DoodlePalette(
    surface: Color(0xFF1A1C1E),
    primary: Color(0xFFE2E2E6),
    secondary: Color(0xFF3F4759),
    success: Color(0xFF81C784),
    error: Color(0xFFE57373),
    container: Color(0xFF2D2F31),
    border: Color(0xFF44474A),
    muted: Color(0xFFC6C6CA),
    field: Color(0xFF2D2F31),
    soft: Color(0xFF3F4759),
    glow: Color(0x332E77D0),
    onAccent: Color(0xFFE2E2E6),
  );

  @override
  DoodlePalette copyWith({
    Color? surface,
    Color? primary,
    Color? secondary,
    Color? success,
    Color? error,
    Color? container,
    Color? border,
    Color? muted,
    Color? field,
    Color? soft,
    Color? glow,
    Color? onAccent,
  }) => DoodlePalette(
    surface: surface ?? this.surface,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    success: success ?? this.success,
    error: error ?? this.error,
    container: container ?? this.container,
    border: border ?? this.border,
    muted: muted ?? this.muted,
    field: field ?? this.field,
    soft: soft ?? this.soft,
    glow: glow ?? this.glow,
    onAccent: onAccent ?? this.onAccent,
  );

  @override
  DoodlePalette lerp(ThemeExtension<DoodlePalette>? other, double t) {
    if (other is! DoodlePalette) return this;
    return DoodlePalette(
      surface: Color.lerp(surface, other.surface, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      container: Color.lerp(container, other.container, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      field: Color.lerp(field, other.field, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

extension DoodleTheme on BuildContext {
  DoodlePalette get doodle => Theme.of(this).extension<DoodlePalette>()!;
}

class TaskReminderApp extends StatefulWidget {
  const TaskReminderApp({super.key});

  static final themeMode = ValueNotifier(ThemeMode.light);

  @override
  State<TaskReminderApp> createState() => _TaskReminderAppState();
}

class _TaskReminderAppState extends State<TaskReminderApp> {
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
    final name = user.trim();
    await AuthCache.save(name, password);
    if (mounted) {
      setState(() {
        _userName = name;
        _password = password;
      });
    }
    return null;
  }

  Future<String?> _register(String user, String password) async {
    return _login(user, password);
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
    if (newPassword.length < 8) {
      return 'New password must be at least 8 characters.';
    }
    if (newPassword != confirmation) {
      return 'Password confirmation does not match.';
    }
    await AuthCache.save(_userName!, newPassword);
    if (mounted) setState(() => _password = newPassword);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: TaskReminderApp.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'task-reminder',
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
    final colors = dark ? DoodlePalette.dark : DoodlePalette.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.secondary,
      brightness: brightness,
      surface: colors.surface,
      primary: colors.primary,
      secondary: colors.secondary,
      error: colors.error,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [colors],
      scaffoldBackgroundColor: colors.surface,
      fontFamily: 'Bricolage Grotesque',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: colors.primary,
        displayColor: colors.primary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.container,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border, width: 1.2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.field,
        labelStyle: TextStyle(color: colors.muted),
        hintStyle: TextStyle(color: colors.muted),
        prefixIconColor: colors.primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: dark ? colors.surface : AppColors.surface,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.border, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.primary),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: colors.primary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.container,
        selectedColor: colors.secondary,
        checkmarkColor: colors.primary,
        labelStyle: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide(color: colors.border, width: 1.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.container,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border, width: 1.4),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.success;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(
          dark ? colors.surface : AppColors.surface,
        ),
        side: BorderSide(color: colors.border, width: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 88,
        elevation: 0,
        backgroundColor: colors.container,
        indicatorColor: colors.secondary,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(color: colors.primary, fontWeight: FontWeight.w800),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: colors.primary,
            fill: states.contains(WidgetState.selected) ? 1 : 0,
          );
        }),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: colors.primary, width: 1.2),
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
  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _password.text.length < 8) {
      setState(
        () => _error =
            'Enter a username and a password with at least 8 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = _registering
        ? await widget.onRegister(_user.text, _password.text)
        : await widget.onLogin(_user.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
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
                      _registering ? 'Create account' : 'Sign in',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use offline first. Backend is only needed when syncing.',
                      style: TextStyle(color: colors.muted),
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
                                ? 'Already have an account'
                                : 'Create account',
                          ),
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
  Size get preferredSize => const Size.fromHeight(98);

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return AppBar(
      toolbarHeight: 98,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.surface,
      titleSpacing: 24,
      title: Row(
        children: [
          Icon(Icons.draw_outlined, color: colors.primary, size: 30),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              'task-reminder',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.primary,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
      actions: [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: TaskReminderApp.themeMode,
          builder: (context, mode, _) {
            final dark = mode == ThemeMode.dark;
            return IconButton(
              tooltip: dark ? 'Light mode' : 'Dark mode',
              onPressed: () => TaskReminderApp.themeMode.value = dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode_outlined),
            );
          },
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

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
  TaskStore? _store;
  List<TaskItem> _tasks = [];
  List<TaskAssignment> _assignments = [];
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = _store ?? await TaskStore.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _tasks = store.tasks();
      _assignments = store.assignments();
    });
    await LocalReminderService.instance.reschedule(
      tasks: _tasks,
      assignments: _assignments,
    );
  }

  Future<TaskItem> _addTask(
    String title,
    String note, {
    TaskPriority priority = TaskPriority.normal,
    TaskIconKind iconKind = TaskIconKind.study,
    int estimateMinutes = 15,
  }) async {
    final now = DateTime.now();
    final task = await _store!.addTask(
      TaskItem(
        id: const Uuid().v4(),
        title: title.trim(),
        note: note.trim(),
        priority: priority,
        iconKind: iconKind,
        estimateMinutes: estimateMinutes,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _load();
    return task;
  }

  Future<void> _assign(
    TaskItem task,
    DateTime date, {
    TimeOfDay? reminderTime,
  }) async {
    final now = DateTime.now();
    await _store!.addAssignment(
      TaskAssignment(
        id: const Uuid().v4(),
        taskId: task.id,
        date: dateOnly(date),
        createdAt: now,
        updatedAt: now,
        reminderHour: reminderTime?.hour ?? 8,
        reminderMinute: reminderTime?.minute ?? 0,
      ),
    );
    await _load();
  }

  Future<void> _updateTaskDetails(
    TaskItem task,
    String title,
    String note,
    TaskIconKind iconKind,
    TaskPriority priority,
    int estimateMinutes,
  ) async {
    await _store!.updateTask(
      task.copyWith(
        title: title.trim(),
        note: note.trim(),
        iconKind: iconKind,
        priority: priority,
        estimateMinutes: estimateMinutes,
        updatedAt: DateTime.now(),
      ),
    );
    await _load();
  }

  Future<void> _markDone(TaskAssignment assignment) async {
    await _store!.markDone(assignment.id);
    await _load();
  }

  Future<void> _unmarkDone(TaskAssignment assignment) async {
    await _store!.unmarkDone(assignment.id);
    await _load();
  }

  Future<void> _removeAssignment(TaskAssignment assignment) async {
    await _store!.removeAssignment(assignment.id);
    await _load();
  }

  Future<void> _snoozeAssignment(
    TaskAssignment assignment,
    Duration offset,
  ) async {
    await _store!.snoozeAssignment(assignment.id, offset);
    await _load();
  }

  Future<void> _removeTask(TaskItem task) async {
    await _store!.removeTask(task.id);
    await _load();
  }

  Future<String?> _sync() async {
    try {
      final baseUrl = await BackendConfig.loadUrl();
      if (baseUrl.trim().isEmpty) {
        return 'Enter a Backend URL in Account before syncing.';
      }
      final data = await TaskSyncService(
        baseUrl: baseUrl,
        userName: widget.userName,
        password: widget.password,
      ).syncTwoWay(_tasks, _assignments);
      await _store!.replaceAll(data);
      await _load();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = [
      OverviewPage(
        tasks: _tasks,
        assignments: _assignments,
        onDone: _markDone,
        onUndoDone: _unmarkDone,
        onRemoveAssignment: _removeAssignment,
      ),
      DailyPage(
        tasks: _tasks,
        assignments: _assignments,
        onDone: _markDone,
        onUndoDone: _unmarkDone,
        onSnooze: _snoozeAssignment,
      ),
      WorkListPage(
        tasks: _tasks,
        assignments: _assignments,
        onAdd: _addTask,
        onAssignToday: (task) => _assign(task, DateTime.now()),
        onAssignDate: _assign,
        onUpdateTask: _updateTaskDetails,
        onRemoveTask: _removeTask,
        onDone: _markDone,
        onUndoDone: _unmarkDone,
        onSnooze: _snoozeAssignment,
        onRemoveAssignment: _removeAssignment,
      ),
      AccountPage(
        tasks: _tasks,
        assignments: _assignments,
        userName: widget.userName,
        password: widget.password,
        onSync: _sync,
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
                icon: Icon(Icons.query_stats_outlined),
                selectedIcon: Icon(Icons.query_stats),
                label: 'Overview',
              ),
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: 'Daily',
              ),
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment),
                label: 'Work list',
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
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
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
      style: Theme.of(
        context,
      ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.tasks,
    required this.assignments,
    required this.onDone,
    required this.onUndoDone,
    required this.onRemoveAssignment,
  });

  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
  final ValueChanged<TaskAssignment> onDone;
  final ValueChanged<TaskAssignment> onUndoDone;
  final ValueChanged<TaskAssignment> onRemoveAssignment;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  List<DateTime?> _calendarSlots() {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leadingBlanks = firstDay.weekday - 1;
    final slots = <DateTime?>[
      for (var index = 0; index < leadingBlanks; index++) null,
      for (var day = 1; day <= daysInMonth; day++)
        DateTime(_visibleMonth.year, _visibleMonth.month, day),
    ];
    while (slots.length % 7 != 0) {
      slots.add(null);
    }
    return slots;
  }

  void _moveMonth(int offset) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + offset,
      );
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _visibleMonth.year == now.year && _visibleMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final slots = _calendarSlots();
    final monthTitle = 'Month ${_visibleMonth.month}/${_visibleMonth.year}';

    return PageList(
      children: [
        SectionCard(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Previous month',
                    onPressed: () => _moveMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      monthTitle.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Next month',
                    onPressed: _isCurrentMonth ? null : () => _moveMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  CalendarWeekdayLabel('T2'),
                  CalendarWeekdayLabel('T3'),
                  CalendarWeekdayLabel('T4'),
                  CalendarWeekdayLabel('T5'),
                  CalendarWeekdayLabel('T6'),
                  CalendarWeekdayLabel('T7'),
                  CalendarWeekdayLabel('CN'),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  return GridView.builder(
                    itemCount: slots.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: constraints.maxWidth < 430
                          ? 0.78
                          : 0.95,
                    ),
                    itemBuilder: (context, index) {
                      final day = slots[index];
                      final items =
                          day == null
                                ? <TaskAssignment>[]
                                : widget.assignments
                                      .where(
                                        (item) => isSameDay(item.date, day),
                                      )
                                      .toList()
                            ..sort((a, b) {
                              if (a.done != b.done) return a.done ? 1 : -1;
                              return a.createdAt.compareTo(b.createdAt);
                            });
                      return CalendarDayCell(
                        date: day,
                        isToday: day != null && isSameDay(day, today),
                        assignments: items,
                        onTap: day == null
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (context) => DayTasksDialog(
                                  day: day,
                                  tasks: widget.tasks,
                                  assignments: items,
                                  onDone: widget.onDone,
                                  onUndoDone: widget.onUndoDone,
                                  onRemoveAssignment: widget.onRemoveAssignment,
                                ),
                              ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DailyPage extends StatefulWidget {
  const DailyPage({
    super.key,
    required this.tasks,
    required this.assignments,
    required this.onDone,
    required this.onUndoDone,
    required this.onSnooze,
  });

  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
  final ValueChanged<TaskAssignment> onDone;
  final ValueChanged<TaskAssignment> onUndoDone;
  final Future<void> Function(TaskAssignment assignment, Duration offset)
  onSnooze;

  @override
  State<DailyPage> createState() => _DailyPageState();
}

class _DailyPageState extends State<DailyPage> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final today = DateTime.now();
    final pending =
        widget.assignments
            .where((item) => isSameDay(item.date, today) && !item.done)
            .toList()
          ..sort((a, b) => compareFocusAssignments(a, b, widget.tasks));
    final done =
        widget.assignments
            .where((item) => isSameDay(item.date, today) && item.done)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final focusMinutes = pending.fold<int>(
      0,
      (sum, assignment) =>
          sum + taskFor(widget.tasks, assignment).estimateMinutes,
    );
    final streak = currentDoneStreak(widget.assignments);

    return PageList(
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: PageTitle('My Day')),
                  PriorityPill(
                    icon: Icons.local_fire_department_outlined,
                    label: '$streak days',
                    color: colors.success,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ProgressSummary(
                done: done.length,
                total: pending.length + done.length,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PriorityPill(
                    icon: Icons.flag_outlined,
                    label: '${pending.length} pending',
                    color: colors.error,
                  ),
                  PriorityPill(
                    icon: Icons.timer_outlined,
                    label: '$focusMinutes min',
                    color: colors.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (pending.isEmpty)
                Center(
                  child: Column(
                    children: [
                      const ReminderArt(
                        icon: Icons.favorite,
                        color: Color(0xFFFFC7D1),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'All clear today',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 620 ? 2 : 3;
                    return GridView.builder(
                      itemCount: pending.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: columns == 2 ? .68 : .86,
                      ),
                      itemBuilder: (context, index) {
                        final assignment = pending[index];
                        final task = taskFor(widget.tasks, assignment);
                        return DailyReminderCard(
                          task: task,
                          assignment: assignment,
                          onDoubleTap: () => widget.onDone(assignment),
                          onSnooze15: () => widget.onSnooze(
                            assignment,
                            const Duration(minutes: 15),
                          ),
                          onSnoozeTomorrow: () => widget.onSnooze(
                            assignment,
                            const Duration(days: 1),
                          ),
                        );
                      },
                    );
                  },
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
                  const Expanded(child: PageTitle('Done')),
                  Text(
                    '${done.length}',
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  IconButton(
                    tooltip: _showDone ? 'Collapse Done' : 'Expand Done',
                    onPressed: done.isEmpty
                        ? null
                        : () => setState(() => _showDone = !_showDone),
                    icon: Icon(
                      _showDone ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
                ],
              ),
              if (_showDone) ...[
                const SizedBox(height: 14),
                if (done.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No completed tasks yet.',
                      style: TextStyle(color: colors.muted),
                    ),
                  )
                else
                  ...done.map(
                    (assignment) => TaskAssignmentTile(
                      task: taskFor(widget.tasks, assignment),
                      assignment: assignment,
                      trailing: IconButton(
                        tooltip: 'Undo',
                        onPressed: () => widget.onUndoDone(assignment),
                        icon: const Icon(Icons.undo),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class WorkListPage extends StatefulWidget {
  const WorkListPage({
    super.key,
    required this.tasks,
    required this.assignments,
    required this.onAdd,
    required this.onAssignToday,
    required this.onAssignDate,
    required this.onUpdateTask,
    required this.onRemoveTask,
    required this.onDone,
    required this.onUndoDone,
    required this.onSnooze,
    required this.onRemoveAssignment,
  });

  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
  final Future<TaskItem> Function(
    String title,
    String note, {
    TaskPriority priority,
    TaskIconKind iconKind,
    int estimateMinutes,
  })
  onAdd;
  final Future<void> Function(TaskItem task) onAssignToday;
  final Future<void> Function(
    TaskItem task,
    DateTime date, {
    TimeOfDay? reminderTime,
  })
  onAssignDate;
  final Future<void> Function(
    TaskItem task,
    String title,
    String note,
    TaskIconKind iconKind,
    TaskPriority priority,
    int estimateMinutes,
  )
  onUpdateTask;
  final Future<void> Function(TaskItem task) onRemoveTask;
  final ValueChanged<TaskAssignment> onDone;
  final ValueChanged<TaskAssignment> onUndoDone;
  final Future<void> Function(TaskAssignment assignment, Duration offset)
  onSnooze;
  final ValueChanged<TaskAssignment> onRemoveAssignment;

  @override
  State<WorkListPage> createState() => _WorkListPageState();
}

class _WorkListPageState extends State<WorkListPage> {
  bool _showAll = false;

  Future<void> _addTaskFromDialog() async {
    final result = await showDialog<AddTaskDialogResult>(
      context: context,
      builder: (context) => const AddTaskDialog(),
    );
    if (result == null) return;
    final task = await widget.onAdd(
      result.title,
      result.note,
      priority: result.priority,
      iconKind: result.iconKind,
      estimateMinutes: result.estimateMinutes,
    );
    for (final date in result.dates) {
      await widget.onAssignDate(task, date, reminderTime: result.reminderTime);
    }
    if (!mounted) return;
    final message = result.dates.isEmpty
        ? 'Saved "${result.title}" to All Tasks'
        : 'Saved "${result.title}" and added ${result.dates.length} schedules';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scheduleTask(TaskItem task) async {
    final result = await showDialog<TaskScheduleResult>(
      context: context,
      builder: (context) => ScheduleTaskDialog(task: task),
    );
    if (result == null) return;
    await widget.onUpdateTask(
      task,
      result.title,
      result.note,
      result.iconKind,
      result.priority,
      result.estimateMinutes,
    );
    if (result.dates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved changes for "${result.title}"')),
      );
      return;
    }
    for (final date in result.dates) {
      await widget.onAssignDate(task, date, reminderTime: result.reminderTime);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved "${result.title}" and added ${result.dates.length} schedules',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final today = DateTime.now();
    final todayItems =
        widget.assignments.where((item) => isSameDay(item.date, today)).toList()
          ..sort((a, b) {
            if (a.done != b.done) return a.done ? 1 : -1;
            return a.createdAt.compareTo(b.createdAt);
          });
    final frequent = topFrequentTasks(widget.tasks, widget.assignments);
    final visibleTasks = _showAll ? widget.tasks : frequent.take(5).toList();

    return PageList(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DoodleSectionHeader(
              title: 'Today',
              icon: Icons.star,
              accent: colors.soft,
            ),
            const SizedBox(height: 14),
            if (todayItems.isEmpty)
              DoodlePanel(
                shadowColor: colors.glow,
                child: Text(
                  'No tasks for today.',
                  style: TextStyle(color: colors.muted),
                ),
              )
            else
              ...todayItems.map(
                (assignment) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TodayWorkRow(
                    task: taskFor(widget.tasks, assignment),
                    assignment: assignment,
                    onDone: () => widget.onDone(assignment),
                    onUndoDone: () => widget.onUndoDone(assignment),
                    onSnooze: () => widget.onSnooze(
                      assignment,
                      const Duration(minutes: 15),
                    ),
                    onRemove: () => widget.onRemoveAssignment(assignment),
                  ),
                ),
              ),
          ],
        ),
        const HandDrawnDivider(),
        DoodleSectionHeader(
          title: 'All Tasks',
          icon: Icons.history,
          accent: colors.secondary,
          tiltRight: true,
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.tasks.length > 5)
                TextButton.icon(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more),
                  label: Text(_showAll ? 'Less' : 'More'),
                ),
              DoodleIconButton(
                tooltip: 'Add task',
                icon: Icons.add,
                label: 'Add',
                onPressed: _addTaskFromDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (visibleTasks.isEmpty)
          DoodlePanel(
            shadowColor: colors.glow,
            child: Text('No tasks yet.', style: TextStyle(color: colors.muted)),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 680 ? 1 : 2;
              return GridView.builder(
                itemCount: visibleTasks.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: constraints.maxWidth < 420 ? 3.0 : 3.8,
                ),
                itemBuilder: (context, index) {
                  final task = visibleTasks[index];
                  return LibraryWorkRow(
                    task: task,
                    onAssignToday: () => widget.onAssignToday(task),
                    onSchedule: () => _scheduleTask(task),
                    onDelete: () => widget.onRemoveTask(task),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.date,
    required this.isToday,
    required this.assignments,
    required this.onTap,
  });

  final DateTime? date;
  final bool isToday;
  final List<TaskAssignment> assignments;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      final colors = context.doodle;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.container.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    final colors = context.doodle;
    final visible = assignments.take(9).toList();
    final rows = [
      visible.take(3).toList(),
      visible.skip(3).take(3).toList(),
      visible.skip(6).take(3).toList(),
    ].where((items) => items.isNotEmpty).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('calendar-${DateFormat('yyyy-MM-dd').format(date!)}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isToday
                ? colors.success.withValues(alpha: .2)
                : colors.container,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday ? colors.success : colors.border,
              width: isToday ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: Text(
                  '${date!.day}',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 20,
                bottom: 0,
                child: rows.isEmpty
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.topCenter,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: 84,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final row in rows)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        for (final assignment in row)
                                          CalendarStatusIcon(
                                            done: assignment.done,
                                          ),
                                        for (
                                          var index = row.length;
                                          index < 3;
                                          index++
                                        )
                                          const SizedBox(width: 14, height: 14),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
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

class CalendarWeekdayLabel extends StatelessWidget {
  const CalendarWeekdayLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class CalendarStatusIcon extends StatelessWidget {
  const CalendarStatusIcon({super.key, required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: done ? colors.success : colors.error,
        shape: BoxShape.circle,
      ),
      child: Icon(
        done ? Icons.check : Icons.close,
        color: Colors.white,
        size: 10,
      ),
    );
  }
}

class DayTasksDialog extends StatelessWidget {
  const DayTasksDialog({
    super.key,
    required this.day,
    required this.tasks,
    required this.assignments,
    required this.onDone,
    required this.onUndoDone,
    required this.onRemoveAssignment,
  });

  final DateTime day;
  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
  final ValueChanged<TaskAssignment> onDone;
  final ValueChanged<TaskAssignment> onUndoDone;
  final ValueChanged<TaskAssignment> onRemoveAssignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final dayTasks =
        assignments
            .map((assignment) => (assignment, taskFor(tasks, assignment)))
            .toList()
          ..sort((a, b) {
            if (a.$1.done != b.$1.done) return a.$1.done ? 1 : -1;
            return a.$1.createdAt.compareTo(b.$1.createdAt);
          });

    return AlertDialog(
      title: Text(shortDateFormat.format(day)),
      content: SizedBox(
        width: 520,
        child: dayTasks.isEmpty
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No tasks on this day.',
                  style: TextStyle(color: colors.muted),
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in dayTasks)
                      TaskAssignmentTile(
                        task: item.$2,
                        assignment: item.$1,
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            PopupMenuButton<String>(
                              tooltip: 'Task actions',
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) {
                                Navigator.of(context).pop();
                                if (value == 'toggle') {
                                  item.$1.done
                                      ? onUndoDone(item.$1)
                                      : onDone(item.$1);
                                } else if (value == 'remove') {
                                  onRemoveAssignment(item.$1);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: ListTile(
                                    leading: Icon(
                                      item.$1.done
                                          ? Icons.undo
                                          : Icons.check_circle_outline,
                                    ),
                                    title: Text(
                                      item.$1.done
                                          ? 'Mark as pending'
                                          : 'Mark as done',
                                    ),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Remove from this day'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class StatusCount extends StatelessWidget {
  const StatusCount({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$count',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class MiniStat extends StatelessWidget {
  const MiniStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.soft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(color: colors.muted)),
          Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class DailyReminderCard extends StatelessWidget {
  const DailyReminderCard({
    super.key,
    required this.task,
    required this.assignment,
    required this.onDoubleTap,
    required this.onSnooze15,
    required this.onSnoozeTomorrow,
  });

  final TaskItem task;
  final TaskAssignment assignment;
  final VoidCallback onDoubleTap;
  final VoidCallback onSnooze15;
  final VoidCallback onSnoozeTomorrow;

  @override
  Widget build(BuildContext context) {
    final style = reminderStyleFor(task.iconKind, context: context);
    final colors = context.doodle;
    return Material(
      color: colors.container,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ReminderArt(icon: style.icon, color: style.color),
              const SizedBox(height: 12),
              Text(
                task.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                taskReminderLabel(task, assignment),
                style: TextStyle(
                  color: colors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  if (task.priority != TaskPriority.none)
                    IconButton(
                      tooltip: 'Snooze 15 minutes',
                      onPressed: onSnooze15,
                      icon: const Icon(Icons.snooze_outlined),
                    ),
                  IconButton(
                    tooltip: 'Move to tomorrow',
                    onPressed: onSnoozeTomorrow,
                    icon: const Icon(Icons.next_plan_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PriorityPill extends StatelessWidget {
  const PriorityPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border, width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderArt extends StatelessWidget {
  const ReminderArt({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Container(
      width: 41,
      height: 41,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .45),
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.border.withValues(alpha: .9),
          width: 2,
        ),
      ),
      child: Icon(icon, size: 29, color: colors.primary),
    );
  }
}

class DoodlePanel extends StatelessWidget {
  const DoodlePanel({
    super.key,
    required this.child,
    this.shadowColor = AppColors.primarySoft,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color shadowColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.container,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(8),
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(12),
        ),
        border: Border.all(color: colors.border, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? colors.glow
                : shadowColor,
            offset: const Offset(4, 4),
            blurRadius: Theme.of(context).brightness == Brightness.dark
                ? 10
                : 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

class DoodleSectionHeader extends StatelessWidget {
  const DoodleSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    this.trailing,
    this.tiltRight = false,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget? trailing;
  final bool tiltRight;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final titleRow = Transform.rotate(
      angle: tiltRight ? 0.018 : -0.018,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 21),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (trailing != null && constraints.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: titleRow),
            ?trailing,
          ],
        );
      },
    );
  }
}

class DoodleIconButton extends StatelessWidget {
  const DoodleIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: label == null ? const SizedBox.shrink() : Text(label!),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        backgroundColor: colors.container,
        side: BorderSide(color: colors.border, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return Tooltip(message: tooltip, child: button);
  }
}

class HandDrawnDivider extends StatelessWidget {
  const HandDrawnDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Transform.rotate(
      angle: -0.012,
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
          color: colors.border,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class TodayWorkRow extends StatelessWidget {
  const TodayWorkRow({
    super.key,
    required this.task,
    required this.assignment,
    required this.onDone,
    required this.onUndoDone,
    required this.onSnooze,
    required this.onRemove,
  });

  final TaskItem task;
  final TaskAssignment assignment;
  final VoidCallback onDone;
  final VoidCallback onUndoDone;
  final VoidCallback onSnooze;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return DoodlePanel(
      child: Row(
        children: [
          Checkbox(
            value: assignment.done,
            onChanged: (_) => assignment.done ? onUndoDone() : onDone(),
            side: BorderSide(color: colors.border, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: assignment.done ? colors.muted : colors.primary,
                    decoration: assignment.done
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${priorityLabel(task.priority)} - ${task.estimateMinutes} min - ${taskReminderLabel(task, assignment)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!assignment.done && task.priority != TaskPriority.none)
            IconButton(
              tooltip: 'Snooze 15 minutes',
              onPressed: onSnooze,
              icon: const Icon(Icons.snooze_outlined),
            ),
          IconButton(
            tooltip: 'Remove from today',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class LibraryWorkRow extends StatelessWidget {
  const LibraryWorkRow({
    super.key,
    required this.task,
    required this.onAssignToday,
    required this.onSchedule,
    required this.onDelete,
  });

  final TaskItem task;
  final VoidCallback onAssignToday;
  final VoidCallback onSchedule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final iconColor = taskIconColor(task.iconKind, context: context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSchedule,
        child: DoodlePanel(
          shadowColor: AppColors.secondary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: .24),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border, width: 1.4),
                ),
                child: Icon(
                  taskIconData(task.iconKind),
                  color: iconColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${priorityLabel(task.priority)} - ${task.estimateMinutes} min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Schedule',
                onPressed: onSchedule,
                icon: const Icon(Icons.event_repeat_outlined),
              ),
              IconButton(
                key: ValueKey('add-today-${normalizedTaskTitle(task.title)}'),
                tooltip: 'Add today',
                onPressed: onAssignToday,
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddTaskDialogResult {
  const AddTaskDialogResult({
    required this.title,
    required this.note,
    required this.iconKind,
    required this.dates,
    required this.priority,
    required this.estimateMinutes,
    this.reminderTime,
  });

  final String title;
  final String note;
  final TaskIconKind iconKind;
  final List<DateTime> dates;
  final TaskPriority priority;
  final int estimateMinutes;
  final TimeOfDay? reminderTime;
}

class AddTaskDialog extends StatefulWidget {
  const AddTaskDialog({super.key});

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class FeatureToggleHeader extends StatelessWidget {
  const FeatureToggleHeader({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: value
                  ? colors.secondary.withValues(alpha: .65)
                  : colors.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border, width: 1.1),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _monthDay = TextEditingController();
  TaskIconKind _iconKind = TaskIconKind.study;
  TaskPriority _priority = TaskPriority.normal;
  int _estimateMinutes = 15;
  TimeOfDay? _reminderTime;
  List<DateTime> _dates = const [];
  String _scheduleLabel = 'No schedule set';
  String? _scheduleKey;
  bool _iconEnabled = false;
  bool _priorityEnabled = false;
  bool _scheduleEnabled = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _monthDay.dispose();
    super.dispose();
  }

  void _clearSchedule() {
    setState(() {
      _scheduleLabel = 'No schedule set';
      _scheduleKey = null;
      _dates = const [];
      _error = null;
    });
  }

  void _setPriorityEnabled(bool value) {
    setState(() {
      _priorityEnabled = value;
      if (!value) _reminderTime = null;
      _error = null;
    });
  }

  void _setScheduleEnabled(bool value) {
    if (!value) {
      _clearSchedule();
      setState(() => _scheduleEnabled = false);
      return;
    }
    setState(() {
      _scheduleEnabled = true;
      _error = null;
    });
  }

  void _toggleSchedule(String key, String label, List<DateTime> dates) {
    if (_scheduleKey == key) {
      _clearSchedule();
      return;
    }
    setState(() {
      _scheduleLabel = label;
      _scheduleKey = key;
      _dates = dates;
      _error = null;
    });
  }

  void _save() {
    final parsed = parseQuickTask(_title.text);
    final title = parsed.title;
    final priority =
        parsed.priority ?? (_priorityEnabled ? _priority : TaskPriority.none);
    if (title.isEmpty) {
      setState(() => _error = 'Enter a task name first.');
      return;
    }
    Navigator.of(context).pop(
      AddTaskDialogResult(
        title: title,
        note: _note.text.trim(),
        iconKind:
            parsed.iconKind ?? (_iconEnabled ? _iconKind : TaskIconKind.study),
        dates: _dates.isEmpty ? parsed.dates : _dates,
        priority: priority,
        estimateMinutes: parsed.estimateMinutes ?? _estimateMinutes,
        reminderTime: priority == TaskPriority.none
            ? null
            : parsed.reminderTime ?? _reminderTime,
      ),
    );
  }

  void _setMonthDaySchedule() {
    final days = parseMonthDays(_monthDay.text);
    if (days.isEmpty) {
      setState(
        () => _error =
            'Enter one or more month days from 1 to 31, separated by commas.',
      );
      return;
    }
    final dates = nextMonthDayDatesForDays(days);
    if (dates.isEmpty) {
      setState(
        () => _error = 'No matching schedule is available for these days.',
      );
      return;
    }
    _toggleSchedule(
      'month:${days.join(',')}',
      monthDayScheduleLabel(days),
      dates,
    );
  }

  Future<void> _pickReminderTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (value != null) setState(() => _reminderTime = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final compact = MediaQuery.sizeOf(context).width < 430;
    const weekdays = [
      (1, 'Mon'),
      (2, 'Tue'),
      (3, 'Wed'),
      (4, 'Thu'),
      (5, 'Fri'),
      (6, 'Sat'),
      (7, 'Sun'),
    ];

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 32,
        vertical: compact ? 18 : 24,
      ),
      titlePadding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 14 : 18,
        compact ? 10 : 14,
        0,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Add Task',
              style: TextStyle(
                fontSize: compact ? 27 : 32,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      contentPadding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 14 : 20,
        compact ? 18 : 24,
        0,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('add-task-title-input'),
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Quick Add',
                  hintText: compact
                      ? 'Example: Report tomorrow 9:00'
                      : 'Example: Submit report tomorrow 9:00 !high ~45m #work',
                  prefixIcon: const Icon(Icons.task_alt_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('add-task-note-input'),
                controller: _note,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FeatureToggleHeader(
                label: 'Icon',
                icon: Icons.category_outlined,
                value: _iconEnabled,
                onChanged: (value) => setState(() => _iconEnabled = value),
              ),
              if (_iconEnabled) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final iconKind in TaskIconKind.values)
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(taskIconData(iconKind), size: 13),
                        label: Text(taskIconLabel(iconKind)),
                        selected: _iconKind == iconKind,
                        onSelected: (_) => setState(() => _iconKind = iconKind),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              FeatureToggleHeader(
                label: 'Priority',
                icon: Icons.flag_outlined,
                value: _priorityEnabled,
                onChanged: _setPriorityEnabled,
              ),
              if (_priorityEnabled) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final priority in TaskPriority.values.where(
                      (value) => value != TaskPriority.none,
                    ))
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(priorityIcon(priority), size: 13),
                        label: Text(priorityLabel(priority)),
                        selected: _priority == priority,
                        onSelected: (_) => setState(() {
                          _priority = priority;
                          if (priority == TaskPriority.none) {
                            _reminderTime = null;
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final minutes in [15, 30, 45, 60])
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text('${minutes}m'),
                        selected: _estimateMinutes == minutes,
                        onSelected: (_) =>
                            setState(() => _estimateMinutes = minutes),
                      ),
                    OutlinedButton.icon(
                      onPressed: _pickReminderTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        _reminderTime == null
                            ? 'Reminder'
                            : _reminderTime!.format(context),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              FeatureToggleHeader(
                label: 'Schedule',
                icon: Icons.event_repeat_outlined,
                value: _scheduleEnabled,
                onChanged: _setScheduleEnabled,
              ),
              if (_scheduleEnabled) ...[
                const SizedBox(height: 8),
                Text(
                  _scheduleLabel,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (weekday, label) in weekdays)
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: const Icon(
                          Icons.event_repeat_outlined,
                          size: 13,
                        ),
                        label: Text(label),
                        selected: _scheduleKey == 'weekday:$weekday',
                        onSelected: (_) => _toggleSchedule(
                          'weekday:$weekday',
                          '$label, next 12 times',
                          nextWeekdayDates(weekday),
                        ),
                      ),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.today_outlined, size: 13),
                      label: const Text('Every day'),
                      selected: _scheduleKey == 'daily',
                      onSelected: (_) => _toggleSchedule(
                        'daily',
                        'Every day, next 30 days',
                        nextDailyDates(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('add-task-month-day-input'),
                        controller: _monthDay,
                        keyboardType: TextInputType.text,
                        onSubmitted: (_) => _setMonthDaySchedule(),
                        decoration: const InputDecoration(
                          labelText: 'Month day',
                          hintText: 'Example: 1, 15, 30',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _setMonthDaySchedule,
                        icon: const Icon(Icons.event_repeat_outlined, size: 18),
                        label: Text(
                          _scheduleKey?.startsWith('month:') ?? false
                              ? 'Clear'
                              : 'Set',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Task'),
        ),
      ],
    );
  }
}

class TaskScheduleResult {
  const TaskScheduleResult({
    required this.title,
    required this.note,
    required this.iconKind,
    required this.priority,
    required this.estimateMinutes,
    this.dates = const [],
    this.reminderTime,
  });

  final String title;
  final String note;
  final TaskIconKind iconKind;
  final TaskPriority priority;
  final int estimateMinutes;
  final List<DateTime> dates;
  final TimeOfDay? reminderTime;
}

class ScheduleTaskDialog extends StatefulWidget {
  const ScheduleTaskDialog({super.key, required this.task});

  final TaskItem task;

  @override
  State<ScheduleTaskDialog> createState() => _ScheduleTaskDialogState();
}

class _ScheduleTaskDialogState extends State<ScheduleTaskDialog> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _monthDay = TextEditingController();
  late TaskIconKind _iconKind;
  late TaskPriority _priority;
  late int _estimateMinutes;
  TimeOfDay? _reminderTime;
  List<DateTime> _dates = const [];
  String _scheduleLabel = 'No schedule set';
  String? _scheduleKey;
  bool _iconEnabled = false;
  bool _priorityEnabled = false;
  bool _scheduleEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.text = widget.task.title;
    _note.text = widget.task.note;
    _iconKind = widget.task.iconKind;
    _priority = widget.task.priority;
    _priorityEnabled = widget.task.priority != TaskPriority.none;
    _estimateMinutes = widget.task.estimateMinutes;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _monthDay.dispose();
    super.dispose();
  }

  void _clearSchedule() {
    setState(() {
      _scheduleLabel = 'No schedule set';
      _scheduleKey = null;
      _dates = const [];
      _error = null;
    });
  }

  void _setPriorityEnabled(bool value) {
    setState(() {
      _priorityEnabled = value;
      if (!value) _reminderTime = null;
      _error = null;
    });
  }

  void _setScheduleEnabled(bool value) {
    if (!value) {
      _clearSchedule();
      setState(() => _scheduleEnabled = false);
      return;
    }
    setState(() {
      _scheduleEnabled = true;
      _error = null;
    });
  }

  void _toggleSchedule(String key, String label, List<DateTime> dates) {
    if (_scheduleKey == key) {
      _clearSchedule();
      return;
    }
    setState(() {
      _scheduleLabel = label;
      _scheduleKey = key;
      _dates = dates;
      _error = null;
    });
  }

  void _setMonthDaySchedule() {
    final days = parseMonthDays(_monthDay.text);
    if (days.isEmpty) {
      setState(
        () => _error =
            'Enter one or more month days from 1 to 31, separated by commas.',
      );
      return;
    }
    final dates = nextMonthDayDatesForDays(days);
    if (dates.isEmpty) {
      setState(
        () => _error = 'No matching schedule is available for these days.',
      );
      return;
    }
    _toggleSchedule(
      'month:${days.join(',')}',
      monthDayScheduleLabel(days),
      dates,
    );
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a task name first.');
      return;
    }
    Navigator.of(context).pop(
      TaskScheduleResult(
        title: title,
        note: _note.text.trim(),
        iconKind: _iconKind,
        priority: _priorityEnabled ? _priority : TaskPriority.none,
        estimateMinutes: _estimateMinutes,
        dates: _scheduleEnabled ? _dates : const [],
        reminderTime: _priorityEnabled ? _reminderTime : null,
      ),
    );
  }

  Future<void> _pickReminderTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (value != null) setState(() => _reminderTime = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final compact = MediaQuery.sizeOf(context).width < 430;
    const weekdays = [
      (1, 'Mon'),
      (2, 'Tue'),
      (3, 'Wed'),
      (4, 'Thu'),
      (5, 'Fri'),
      (6, 'Sat'),
      (7, 'Sun'),
    ];

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 32,
        vertical: compact ? 18 : 24,
      ),
      titlePadding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 14 : 18,
        compact ? 10 : 14,
        0,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Task Settings',
              style: TextStyle(
                fontSize: compact ? 27 : 32,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      contentPadding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 14 : 20,
        compact ? 18 : 24,
        0,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('edit-task-title-input'),
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Task name',
                  prefixIcon: Icon(Icons.task_alt_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('edit-task-note-input'),
                controller: _note,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FeatureToggleHeader(
                label: 'Icon',
                icon: Icons.category_outlined,
                value: _iconEnabled,
                onChanged: (value) => setState(() => _iconEnabled = value),
              ),
              if (_iconEnabled) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final iconKind in TaskIconKind.values)
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(taskIconData(iconKind), size: 13),
                        label: Text(taskIconLabel(iconKind)),
                        selected: _iconKind == iconKind,
                        onSelected: (_) => setState(() => _iconKind = iconKind),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              FeatureToggleHeader(
                label: 'Priority',
                icon: Icons.flag_outlined,
                value: _priorityEnabled,
                onChanged: _setPriorityEnabled,
              ),
              if (_priorityEnabled) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final priority in TaskPriority.values.where(
                      (value) => value != TaskPriority.none,
                    ))
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(priorityIcon(priority), size: 13),
                        label: Text(priorityLabel(priority)),
                        selected: _priority == priority,
                        onSelected: (_) => setState(() {
                          _priority = priority;
                          if (priority == TaskPriority.none) {
                            _reminderTime = null;
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final minutes in [15, 30, 45, 60])
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text('${minutes}m'),
                        selected: _estimateMinutes == minutes,
                        onSelected: (_) =>
                            setState(() => _estimateMinutes = minutes),
                      ),
                    OutlinedButton.icon(
                      onPressed: _pickReminderTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        _reminderTime == null
                            ? 'Reminder'
                            : _reminderTime!.format(context),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              FeatureToggleHeader(
                label: 'Schedule',
                icon: Icons.event_repeat_outlined,
                value: _scheduleEnabled,
                onChanged: _setScheduleEnabled,
              ),
              if (_scheduleEnabled) ...[
                const SizedBox(height: 8),
                Text(
                  _scheduleLabel,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (weekday, label) in weekdays)
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: const Icon(
                          Icons.event_repeat_outlined,
                          size: 13,
                        ),
                        label: Text(label),
                        selected: _scheduleKey == 'weekday:$weekday',
                        onSelected: (_) => _toggleSchedule(
                          'weekday:$weekday',
                          '$label, next 12 times',
                          nextWeekdayDates(weekday),
                        ),
                      ),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.today_outlined, size: 13),
                      label: const Text('Every day'),
                      selected: _scheduleKey == 'daily',
                      onSelected: (_) => _toggleSchedule(
                        'daily',
                        'Every day, next 30 days',
                        nextDailyDates(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('edit-task-month-day-input'),
                        controller: _monthDay,
                        keyboardType: TextInputType.text,
                        onSubmitted: (_) => _setMonthDaySchedule(),
                        decoration: const InputDecoration(
                          labelText: 'Month day',
                          hintText: 'Example: 1, 15, 30',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _setMonthDaySchedule,
                        icon: const Icon(Icons.event_repeat_outlined, size: 18),
                        label: Text(
                          _scheduleKey?.startsWith('month:') ?? false
                              ? 'Clear'
                              : 'Set',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Task'),
        ),
      ],
    );
  }
}

List<DateTime> nextWeekdayDates(int weekday) {
  final today = dateOnly(DateTime.now());
  var daysToAdd = weekday - today.weekday;
  if (daysToAdd <= 0) daysToAdd += 7;
  final first = today.add(Duration(days: daysToAdd));
  return List.generate(12, (index) => first.add(Duration(days: 7 * index)));
}

List<DateTime> nextDailyDates() {
  final today = dateOnly(DateTime.now());
  return List.generate(30, (index) => today.add(Duration(days: index)));
}

List<DateTime> nextMonthDayDates(int day) {
  final today = dateOnly(DateTime.now());
  final dates = <DateTime>[];
  var month = today.month;
  var year = today.year;
  for (var attempt = 0; attempt < 36 && dates.length < 12; attempt++) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    if (day <= daysInMonth) {
      final candidate = DateTime(year, month, day);
      if (candidate.isAfter(today)) dates.add(candidate);
    }
    month++;
    if (month > 12) {
      month = 1;
      year++;
    }
  }
  return dates;
}

List<int> parseMonthDays(String raw) {
  final values = <int>{};
  for (final part in raw.split(',')) {
    final day = int.tryParse(part.trim());
    if (day == null || day < 1 || day > 31) return const [];
    values.add(day);
  }
  final days = values.toList()..sort();
  return days;
}

List<DateTime> nextMonthDayDatesForDays(List<int> days) {
  final keyed = <String, DateTime>{};
  for (final day in days) {
    for (final date in nextMonthDayDates(day)) {
      keyed[date.toIso8601String()] = date;
    }
  }
  final dates = keyed.values.toList()..sort();
  return dates;
}

String monthDayScheduleLabel(List<int> days) {
  if (days.length == 1) return 'Day ${days.single} monthly, next 12 times';
  return 'Days ${days.join(', ')} monthly, next 12 times each';
}

class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stats,
  });

  final String title;
  final String subtitle;
  final String stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.container,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTitle(title),
          const SizedBox(height: 14),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.muted,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          FittedBox(
            alignment: Alignment.centerLeft,
            child: Text(
              stats,
              style: const TextStyle(
                fontSize: 42,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TaskLibraryList extends StatelessWidget {
  const TaskLibraryList({super.key, required this.tasks});

  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Text(
        'No tasks yet.',
        style: TextStyle(color: context.doodle.muted),
      );
    }
    return Column(
      children: tasks.map((task) => TaskLibraryTile(task: task)).toList(),
    );
  }
}

class TaskLibraryTile extends StatelessWidget {
  const TaskLibraryTile({super.key, required this.task, this.trailing});

  final TaskItem task;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const TaskIcon(icon: Icons.task_alt_outlined),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (task.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    task.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class TaskAssignmentList extends StatelessWidget {
  const TaskAssignmentList({
    super.key,
    required this.tasks,
    required this.assignments,
    required this.emptyText,
    required this.onDone,
    required this.onUndoDone,
    required this.onMoveTomorrow,
    required this.onReminder,
    required this.onRemove,
  });

  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
  final String emptyText;
  final ValueChanged<TaskAssignment> onDone;
  final ValueChanged<TaskAssignment> onUndoDone;
  final ValueChanged<TaskAssignment> onMoveTomorrow;
  final Future<void> Function(TaskAssignment assignment, TimeOfDay time)
  onReminder;
  final ValueChanged<TaskAssignment> onRemove;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty) {
      return Text(emptyText, style: TextStyle(color: context.doodle.muted));
    }
    return Column(
      children: assignments.map((assignment) {
        final task = taskFor(tasks, assignment);
        return TaskAssignmentTile(
          task: task,
          assignment: assignment,
          trailing: Wrap(
            spacing: 4,
            children: [
              if (!assignment.done)
                IconButton(
                  tooltip: 'Done',
                  onPressed: () => onDone(assignment),
                  icon: const Icon(Icons.check_circle_outline),
                )
              else
                IconButton(
                  tooltip: 'Undo done',
                  onPressed: () => onUndoDone(assignment),
                  icon: const Icon(Icons.undo),
                ),
              if (!assignment.done)
                IconButton(
                  tooltip: 'Tomorrow',
                  onPressed: () => onMoveTomorrow(assignment),
                  icon: const Icon(Icons.next_plan_outlined),
                ),
              if (task.priority != TaskPriority.none)
                IconButton(
                  tooltip: 'Reminder',
                  onPressed: () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: assignment.reminderHour,
                        minute: assignment.reminderMinute,
                      ),
                    );
                    if (value != null) await onReminder(assignment, value);
                  },
                  icon: const Icon(Icons.schedule),
                ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => onRemove(assignment),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class TaskAssignmentTile extends StatelessWidget {
  const TaskAssignmentTile({
    super.key,
    required this.task,
    required this.assignment,
    this.trailing,
  });

  final TaskItem task;
  final TaskAssignment assignment;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          TaskIcon(
            icon: assignment.done
                ? Icons.done_all
                : Icons.radio_button_unchecked,
            muted: assignment.done,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    decoration: assignment.done
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  assignment.done
                      ? 'Done ${shortDateFormat.format(assignment.completedAt!)}'
                      : '${shortDateFormat.format(assignment.date)} - '
                            '${taskReminderLabel(task, assignment)}',
                  style: TextStyle(color: colors.muted),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class TaskIcon extends StatelessWidget {
  const TaskIcon({super.key, required this.icon, this.muted = false});

  final IconData icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return Container(
      width: 41,
      height: 41,
      decoration: BoxDecoration(
        color: muted ? colors.container : colors.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: colors.primary, size: 20),
    );
  }
}

class ProgressSummary extends StatelessWidget {
  const ProgressSummary({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    final value = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Today progress',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '$done/$total',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          minHeight: 10,
          value: value,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: colors.container,
          color: colors.success,
        ),
      ],
    );
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.tasks,
    required this.assignments,
    required this.userName,
    required this.password,
    required this.onSync,
    required this.onReload,
    required this.onLogout,
    required this.onChangePassword,
  });

  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
  final String userName;
  final String password;
  final Future<String?> Function() onSync;
  final Future<void> Function() onReload;
  final VoidCallback onLogout;
  final ChangePasswordCallback onChangePassword;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _backend = TextEditingController();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _message;
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
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final error = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? success;
    });
  }

  Future<void> _sync() async {
    await BackendConfig.saveUrl(_backend.text);
    await _run(widget.onSync, 'Data synced.');
  }

  Future<void> _notification() async {
    await _run(
      () async {
        final granted = await LocalReminderService.instance.requestPermission();
        await LocalReminderService.instance.reschedule(
          tasks: widget.tasks,
          assignments: widget.assignments,
        );
        return granted || kIsWeb
            ? null
            : 'Notification permission has not been granted.';
      },
      kIsWeb
          ? 'Web preview does not support local notifications.'
          : 'Reminders enabled.',
    );
  }

  Future<void> _updatePassword() async {
    await _run(
      () => widget.onChangePassword(_current.text, _next.text, _confirm.text),
      'Password updated.',
    );
    _current.clear();
    _next.clear();
    _confirm.clear();
  }

  Future<void> _checkUpdate() async {
    await BackendConfig.saveUrl(_backend.text);
    await _run(() async {
      final baseUrl = await BackendConfig.loadUrl();
      if (baseUrl.trim().isEmpty) {
        return 'Enter a Backend URL in Account before checking updates.';
      }
      final service = AppUpdateService(baseUrl: baseUrl);
      final info = await service.checkLatest();
      if (!info.available) return 'App is up to date.';
      if (!kIsWeb) {
        final path = await service.downloadApk(info);
        await service.installApk(path);
      }
      return 'Version ${info.versionName}+${info.versionCode} is available: ${info.notes}';
    }, 'Update check complete.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.doodle;
    return PageList(
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _backend,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: BackendConfig.exampleUrl,
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _sync,
                icon: const Icon(Icons.sync),
                label: const Text('Sync'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _notification,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Notification'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _checkUpdate,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Check update'),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: TaskReminderApp.themeMode,
                builder: (context, mode, _) {
                  final dark = mode == ThemeMode.dark;
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      dark ? Icons.dark_mode : Icons.dark_mode_outlined,
                    ),
                    title: const Text('Dark mode'),
                    value: dark,
                    onChanged: (enabled) => TaskReminderApp.themeMode.value =
                        enabled ? ThemeMode.dark : ThemeMode.light,
                  );
                },
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: TextStyle(color: colors.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Change Password',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _updatePassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Update'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

@immutable
class ParsedQuickTask {
  const ParsedQuickTask({
    required this.title,
    this.dates = const [],
    this.reminderTime,
    this.priority,
    this.iconKind,
    this.estimateMinutes,
  });

  final String title;
  final List<DateTime> dates;
  final TimeOfDay? reminderTime;
  final TaskPriority? priority;
  final TaskIconKind? iconKind;
  final int? estimateMinutes;
}

ParsedQuickTask parseQuickTask(String raw) {
  var text = raw.trim();
  final now = DateTime.now();
  var dates = <DateTime>[];
  TimeOfDay? reminderTime;
  TaskPriority? priority;
  TaskIconKind? iconKind;
  int? estimateMinutes;

  final timeMatch = RegExp(
    r'\b([01]?\d|2[0-3])[:h]([0-5]\d)\b',
  ).firstMatch(text);
  if (timeMatch != null) {
    reminderTime = TimeOfDay(
      hour: int.parse(timeMatch.group(1)!),
      minute: int.parse(timeMatch.group(2)!),
    );
    text = text.replaceFirst(timeMatch.group(0)!, ' ');
  }

  final estimateMatch = RegExp(
    r'~\s*(\d{1,3})\s*(p|phut|min|m)?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (estimateMatch != null) {
    estimateMinutes = int.parse(estimateMatch.group(1)!).clamp(5, 240);
    text = text.replaceFirst(estimateMatch.group(0)!, ' ');
  }

  const priorities = {
    '!none': TaskPriority.none,
    '!nopriority': TaskPriority.none,
    '!anytime': TaskPriority.none,
    '!khong': TaskPriority.none,
    '!không': TaskPriority.none,
    '!cao': TaskPriority.high,
    '!high': TaskPriority.high,
    '!normal': TaskPriority.normal,
    '!thuong': TaskPriority.normal,
    '!thường': TaskPriority.normal,
    '!thap': TaskPriority.low,
    '!low': TaskPriority.low,
  };
  for (final entry in priorities.entries) {
    if (text.toLowerCase().contains(entry.key)) {
      priority = entry.value;
      text = text.replaceAll(
        RegExp(RegExp.escape(entry.key), caseSensitive: false),
        ' ',
      );
      break;
    }
  }

  const icons = {
    '#hoc': TaskIconKind.study,
    '#study': TaskIconKind.study,
    '#tap': TaskIconKind.fitness,
    '#gym': TaskIconKind.fitness,
    '#suckhoe': TaskIconKind.health,
    '#health': TaskIconKind.health,
    '#laptop': TaskIconKind.laptop,
    '#work': TaskIconKind.laptop,
    '#vui': TaskIconKind.smile,
    '#travel': TaskIconKind.travel,
  };
  for (final entry in icons.entries) {
    if (text.toLowerCase().contains(entry.key)) {
      iconKind = entry.value;
      text = text.replaceAll(
        RegExp(RegExp.escape(entry.key), caseSensitive: false),
        ' ',
      );
      break;
    }
  }

  final lower = text.toLowerCase();
  if (lower.contains('hom nay') ||
      lower.contains('hôm nay') ||
      lower.contains('today')) {
    dates = [dateOnly(now)];
    text = text.replaceAll(
      RegExp(r'\b(hom nay|hôm nay|today)\b', caseSensitive: false),
      ' ',
    );
  } else if (lower.contains('mai') || lower.contains('tomorrow')) {
    dates = [dateOnly(now.add(const Duration(days: 1)))];
    text = text.replaceAll(
      RegExp(r'\b(ngay mai|ngày mai|mai|tomorrow)\b', caseSensitive: false),
      ' ',
    );
  } else {
    const weekdays = {
      'thu 2': 1,
      'thứ 2': 1,
      'thu 3': 2,
      'thứ 3': 2,
      'thu 4': 3,
      'thứ 4': 3,
      'thu 5': 4,
      'thứ 5': 4,
      'thu 6': 5,
      'thứ 6': 5,
      'thu 7': 6,
      'thứ 7': 6,
      'cn': 7,
      'chu nhat': 7,
      'chủ nhật': 7,
    };
    for (final entry in weekdays.entries) {
      if (lower.contains(entry.key)) {
        dates = nextWeekdayDates(entry.value);
        text = text.replaceAll(
          RegExp(RegExp.escape(entry.key), caseSensitive: false),
          ' ',
        );
        break;
      }
    }
  }

  return ParsedQuickTask(
    title: text.trim().replaceAll(RegExp(r'\s+'), ' '),
    dates: dates,
    reminderTime: reminderTime,
    priority: priority,
    iconKind: iconKind,
    estimateMinutes: estimateMinutes,
  );
}

List<TaskItem> filterTasks(List<TaskItem> tasks, String query) {
  final key = normalizedTaskTitle(query);
  if (key.isEmpty) return tasks;
  return tasks
      .where(
        (task) =>
            normalizedTaskTitle(task.title).contains(key) ||
            normalizedTaskTitle(task.note).contains(key),
      )
      .toList();
}

List<TaskItem> topFrequentTasks(
  List<TaskItem> tasks,
  List<TaskAssignment> assignments,
) {
  final counts = <String, int>{};
  for (final assignment in assignments) {
    counts.update(assignment.taskId, (value) => value + 1, ifAbsent: () => 1);
  }
  final sorted = [...tasks]
    ..sort((a, b) {
      final countCompare = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
      if (countCompare != 0) return countCompare;
      return a.title.compareTo(b.title);
    });
  return sorted;
}

int compareFocusAssignments(
  TaskAssignment a,
  TaskAssignment b,
  List<TaskItem> tasks,
) {
  final taskA = taskFor(tasks, a);
  final taskB = taskFor(tasks, b);
  final priorityCompare = priorityWeight(
    taskB.priority,
  ).compareTo(priorityWeight(taskA.priority));
  if (priorityCompare != 0) return priorityCompare;
  final timeCompare = (a.reminderHour * 60 + a.reminderMinute).compareTo(
    b.reminderHour * 60 + b.reminderMinute,
  );
  if (timeCompare != 0) return timeCompare;
  return taskA.estimateMinutes.compareTo(taskB.estimateMinutes);
}

int priorityWeight(TaskPriority priority) => switch (priority) {
  TaskPriority.high => 3,
  TaskPriority.normal => 2,
  TaskPriority.low => 1,
  TaskPriority.none => 0,
};

IconData priorityIcon(TaskPriority priority) => switch (priority) {
  TaskPriority.high => Icons.priority_high,
  TaskPriority.normal => Icons.flag_outlined,
  TaskPriority.low => Icons.low_priority,
  TaskPriority.none => Icons.event_available_outlined,
};

String priorityLabel(TaskPriority priority) => switch (priority) {
  TaskPriority.high => 'High',
  TaskPriority.normal => 'Normal',
  TaskPriority.low => 'Low',
  TaskPriority.none => 'No priority',
};

String taskReminderLabel(TaskItem task, TaskAssignment assignment) {
  if (task.priority == TaskPriority.none) return 'Anytime today';
  return reminderLabel(assignment);
}

int currentDoneStreak(List<TaskAssignment> assignments) {
  final completedDays = {
    for (final item in assignments.where((item) => item.done))
      dateOnly(item.date).toIso8601String(),
  };
  var cursor = dateOnly(DateTime.now());
  var streak = 0;
  while (completedDays.contains(cursor.toIso8601String())) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

({IconData icon, Color color, Color background}) reminderStyleFor(
  TaskIconKind iconKind, {
  BuildContext? context,
}) {
  return (
    icon: taskIconData(iconKind),
    color: taskIconColor(iconKind, context: context),
    background: context?.doodle.container ?? AppColors.surface,
  );
}

IconData taskIconData(TaskIconKind iconKind) => switch (iconKind) {
  TaskIconKind.study => Icons.menu_book_outlined,
  TaskIconKind.fitness => Icons.fitness_center,
  TaskIconKind.health => Icons.health_and_safety_outlined,
  TaskIconKind.laptop => Icons.laptop_mac_outlined,
  TaskIconKind.smile => Icons.sentiment_satisfied_alt_outlined,
  TaskIconKind.travel => Icons.travel_explore_outlined,
};

String taskIconLabel(TaskIconKind iconKind) => switch (iconKind) {
  TaskIconKind.study => 'Study',
  TaskIconKind.fitness => 'Fitness',
  TaskIconKind.health => 'Health',
  TaskIconKind.laptop => 'Work',
  TaskIconKind.smile => 'Joy',
  TaskIconKind.travel => 'Travel',
};

Color taskIconColor(TaskIconKind iconKind, {BuildContext? context}) {
  final dark =
      context != null && Theme.of(context).brightness == Brightness.dark;
  return switch (iconKind) {
    TaskIconKind.study => dark ? const Color(0xFF8FA8D8) : AppColors.secondary,
    TaskIconKind.fitness =>
      dark ? const Color(0xFFDCA198) : AppColors.primarySoft,
    TaskIconKind.health =>
      dark ? const Color(0xFF81C784) : const Color(0xFFCDECCF),
    TaskIconKind.laptop =>
      dark ? const Color(0xFFAFA4DD) : const Color(0xFFD8D2EE),
    TaskIconKind.smile =>
      dark ? const Color(0xFFE8D27E) : const Color(0xFFFFE9A8),
    TaskIconKind.travel =>
      dark ? const Color(0xFFE7A3B8) : const Color(0xFFFFD7E3),
  };
}

String reminderLabel(TaskAssignment assignment) {
  final hour = assignment.reminderHour.toString().padLeft(2, '0');
  final minute = assignment.reminderMinute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

TaskItem taskFor(List<TaskItem> tasks, TaskAssignment assignment) {
  return tasks.firstWhere(
    (task) => task.id == assignment.taskId,
    orElse: () => TaskItem(
      id: assignment.taskId,
      title: 'Deleted task',
      createdAt: assignment.createdAt,
      updatedAt: assignment.updatedAt,
    ),
  );
}
