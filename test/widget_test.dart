import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:task_reminder/src/app.dart';
import 'package:task_reminder/src/models.dart';
import 'package:task_reminder/src/services.dart';
import 'package:task_reminder/src/storage.dart';

void main() {
  setUp(() {
    TaskReminderApp.themeMode.value = ThemeMode.light;
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('a legacy short password still works after explicit sign out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'legacy',
      AuthCache.passwordKey: '1234',
    });
    await tester.runAsync(() async {
      await AuthCache.load();
      await AuthCache.clear();
    });
    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'legacy');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('account action errors are visible and the busy state recovers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [DoodlePalette.light]),
        home: AccountPage(
          tasks: const [],
          assignments: const [],
          userName: 'preview',
          onSync: () async => throw Exception('Network unavailable'),
          onReload: () async {},
          onLogout: () {},
          onChangePassword: (_, _, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sync = find.widgetWithText(FilledButton, 'Sync');
    await tester.ensureVisible(sync);
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expect(find.text('Network unavailable'), findsOneWidget);
    expect(tester.widget<FilledButton>(sync).onPressed, isNotNull);
  });

  testWidgets(
    'sync shows progress, blocks repeated taps and announces completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final result = Completer<String?>();
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [DoodlePalette.light]),
          home: AccountPage(
            tasks: const [],
            assignments: const [],
            userName: 'preview',
            onSync: () {
              requests++;
              return result.future;
            },
            onReload: () async {},
            onLogout: () {},
            onChangePassword: (_, _, _) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sync = find.widgetWithText(FilledButton, 'Sync');
      await tester.tap(sync);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Syncing tasks…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(sync).onPressed, isNull);
      expect(requests, 1);
      result.complete('Network unavailable');
      await tester.pumpAndSettle();
      expect(find.text('Network unavailable'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.widget<FilledButton>(sync).onPressed, isNotNull);
      final status = tester.widgetList<Semantics>(
        find.ancestor(
          of: find.text('Network unavailable'),
          matching: find.byType(Semantics),
        ),
      );
      expect(
        status.any((widget) => widget.properties.liveRegion == true),
        isTrue,
      );
    },
  );

  testWidgets(
    'a new sync destination requires consent before sending credentials or tasks',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        AuthCache.userKey: 'preview',
        AuthCache.passwordKey: 'preview-password',
        BackendConfig.key: 'https://new-server.example',
      });
      await tester.pumpWidget(const TaskReminderApp());
      await tester.pumpAndSettle();
      await openTab(tester, 3);
      await tester.tap(find.widgetWithText(FilledButton, 'Sync'));
      await tester.pumpAndSettle();
      expect(find.text('Sync with this server?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('https://new-server.example'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sync cancelled. Data stayed on this device.'),
        findsOneWidget,
      );
      expect(await AuthCache.linkedBackend('preview'), isEmpty);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          TaskStore.tasksKeyFor('preview'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('shows the task reminder sign-in screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Backend URL'), findsNothing);
    expect(find.textContaining('No server is required.'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('can sign in offline without backend URL', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'offline-user');
    await tester.enterText(find.byType(TextField).at(1), 'offline-pass');
    await tester.enterText(find.byType(TextField).at(2), 'offline-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthCache.userKey), 'offline-user');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('server password recovery requires an explicit user action', (
    tester,
  ) async {
    var serverLogins = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [DoodlePalette.light]),
        home: AuthScreen(
          hasAccount: true,
          onLogin: (_, _) async => 'Incorrect password.',
          onRegister: (_, _) async => null,
          onServerLogin: (name, password) async {
            serverLogins++;
            expect(name, 'Alice');
            expect(password, 'new-password-456');
            return 'Server unavailable. Local tasks were kept.';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'new-password-456');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(serverLogins, 0);
    final recovery = find.widgetWithText(
      TextButton,
      'Sign in with server password',
    );
    await tester.ensureVisible(recovery);
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    expect(serverLogins, 1);
    expect(
      find.text('Server unavailable. Local tasks were kept.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'offline registration validates confirmation and switches modes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const TaskReminderApp());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'offline-user');
      await tester.enterText(find.byType(TextField).at(1), 'offline-pass');
      await tester.enterText(find.byType(TextField).at(2), 'different-pass');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Password confirmation does not match.'),
        findsOneWidget,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(AuthCache.userKey),
        isNull,
      );

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm password'), findsNothing);
      expect(find.text('Backend URL'), findsNothing);
    },
  );

  testWidgets('can switch to the dark doodle theme', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dark mode'));
    await tester.pumpAndSettle();

    expect(TaskReminderApp.themeMode.value, ThemeMode.dark);
    final context = tester.element(find.text('task-reminder'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(context.doodle.surface, const Color(0xFF1A1C1E));
  });

  testWidgets('keeps the app-style bottom navigation on web', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('check update shows version popup before downloading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      BackendConfig.key: 'https://sync.example.com',
    });
    var installRequests = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [DoodlePalette.light]),
        home: AccountPage(
          tasks: const [],
          assignments: const [],
          userName: 'preview',
          onSync: () async => null,
          onReload: () async {},
          onLogout: () {},
          onChangePassword: (_, _, _) async => null,
          checkLatestForTest: (_) async => const UpdateInfo(
            available: true,
            versionName: '9.9.9',
            versionCode: 999,
            apkUrl: '/releases/app-release-task-reminder.apk',
            notes: 'Popup first.',
          ),
          installUpdateForTest: (_, _) async => installRequests++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Check update'));
    await tester.pumpAndSettle();

    expect(find.text('Update 9.9.9+999'), findsOneWidget);
    expect(find.text('Popup first.'), findsOneWidget);
    expect(installRequests, 0);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Version 9.9.9+999 is available.'), findsOneWidget);
    expect(installRequests, 0);
  });

  testWidgets('work list saves a unique reusable task', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    expect(find.text('Add Task'), findsNothing);
    await addTaskFromAllTasks(tester, 'Viết báo cáo');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(TaskStore.tasksKeyFor('preview')),
      contains('Viết báo cáo'),
    );
  });

  testWidgets('quick add creates a task for today', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await addTaskFromAllTasks(tester, 'Gọi điện cho mẹ', scheduleToday: true);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(TaskStore.tasksKeyFor('preview')),
      contains('Gọi điện cho mẹ'),
    );
    expect(
      prefs.getString(TaskStore.assignmentsKeyFor('preview')),
      contains('taskId'),
    );
  });

  testWidgets('all tasks can schedule by weekday', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await addTaskFromAllTasks(tester, 'Lịch tuần');

    await tester.tap(find.text('Lịch tuần').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-task-title-input')), findsOneWidget);
    await tester.tap(find.text('Schedule').last);
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);

    final monChip = find.widgetWithText(FilterChip, 'Mon');
    await tester.ensureVisible(monChip);
    await tester.pumpAndSettle();
    await tester.tap(monChip);
    await tester.pumpAndSettle();
    expect(find.text('Mon, next 12 times'), findsOneWidget);
    await tester.tap(monChip);
    await tester.pumpAndSettle();
    expect(find.text('No schedule set'), findsOneWidget);
    await tester.tap(monChip);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final assignments =
        prefs.getString(TaskStore.assignmentsKeyFor('preview')) ?? '';
    expect(assignments, contains('taskId'));
    expect(
      RegExp(
        'Lịch tuần',
      ).hasMatch(prefs.getString(TaskStore.tasksKeyFor('preview')) ?? ''),
      isTrue,
    );
  });

  testWidgets('all tasks can schedule every day', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'home');
    await openTab(tester, 2);
    expect(tester.takeException(), isNull, reason: 'all tasks');

    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-task-title-input')),
      'Daily stretch',
    );
    await tester.tap(find.text('Schedule').last);
    await tester.pumpAndSettle();
    final everyDayChip = find.widgetWithText(FilterChip, 'Every day');
    await tester.ensureVisible(everyDayChip);
    await tester.pumpAndSettle();
    await tester.tap(everyDayChip);
    await tester.pumpAndSettle();
    expect(find.text('Every day, next 30 days'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final assignments =
        jsonDecode(
              prefs.getString(TaskStore.assignmentsKeyFor('preview')) ?? '[]',
            )
            as List<Object?>;
    expect(assignments.length, 30);
  });

  testWidgets('add task can schedule multiple weekdays', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-task-title-input')),
      'Gym week',
    );
    await tester.tap(find.text('Schedule').last);
    await tester.pumpAndSettle();

    for (final label in ['Mon', 'Wed', 'Fri']) {
      final chip = find.widgetWithText(FilterChip, label);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    expect(find.text('Mon, Wed, Fri, next 12 times each'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final assignments =
        jsonDecode(
              prefs.getString(TaskStore.assignmentsKeyFor('preview')) ?? '[]',
            )
            as List<Object?>;
    expect(assignments.length, 36);
  });

  testWidgets('all tasks can schedule multiple month days', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'home');
    await openTab(tester, 2);
    expect(tester.takeException(), isNull, reason: 'all tasks');

    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-task-title-input')),
      'Pay bills',
    );
    await tester.tap(find.text('Schedule').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-task-month-day-input')),
      '1, 15',
    );
    final setButton = find.widgetWithText(OutlinedButton, 'Set');
    await tester.ensureVisible(setButton);
    await tester.pumpAndSettle();
    await tester.tap(setButton);
    await tester.pumpAndSettle();
    expect(find.text('Days 1, 15 monthly, next 12 times each'), findsOneWidget);
    final saveButton = find.widgetWithText(FilledButton, 'Save Task');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final assignments =
        jsonDecode(
              prefs.getString(TaskStore.assignmentsKeyFor('preview')) ?? '[]',
            )
            as List<Object?>;
    expect(assignments.length, greaterThanOrEqualTo(20));
  });

  testWidgets('all tasks can save no priority tasks for anytime today', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-task-title-input')),
      'Read docs',
    );
    expect(find.widgetWithText(ChoiceChip, 'Normal'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(TaskStore.tasksKeyFor('preview')),
      contains('"priority":"none"'),
    );
  });

  testWidgets('all tasks can save a custom icon', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await addTaskFromAllTasks(tester, 'Đi Đà Lạt');

    final taskText = find.text('Đi Đà Lạt').last;
    await tester.ensureVisible(taskText);
    await tester.pumpAndSettle();
    await tester.tap(taskText);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Icon').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Travel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(TaskStore.tasksKeyFor('preview')),
      contains('"iconKind":"travel"'),
    );
  });

  testWidgets('task settings can edit title and note', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await addTaskFromAllTasks(tester, 'Task cũ');

    final taskText = find.text('Task cũ').last;
    await tester.ensureVisible(taskText);
    await tester.pumpAndSettle();
    await tester.tap(taskText);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-task-title-input')),
      'Task mới',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-task-note-input')),
      'Ghi chú mới',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final tasks = prefs.getString(TaskStore.tasksKeyFor('preview')) ?? '';
    expect(tasks, contains('Task mới'));
    expect(tasks, contains('Ghi chú mới'));
  });

  testWidgets('daily exposes a one-tap done action and keeps undo available', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await addTaskFromAllTasks(tester, 'Uống nước', scheduleToday: true);

    await openTab(tester, 1);
    expect(find.text('Uống nước'), findsOneWidget);
    expect(find.text('My Day'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    expect(find.byTooltip('Mark Uống nước done'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();
    expect(find.text('Uống nước'), findsNothing);

    await tester.tap(find.byTooltip('Expand Done'));
    await tester.pumpAndSettle();
    expect(find.text('Uống nước'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Uống nước'), findsOneWidget);
  });

  testWidgets('quick add previews recognized task details before saving', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('add-task-title-input')),
      'Nộp báo cáo hôm nay 9:30 !cao ~45p #laptop',
    );
    await tester.pumpAndSettle();

    final detection = find.byKey(const ValueKey('quick-add-detection'));
    expect(detection, findsOneWidget);
    expect(
      find.descendant(
        of: detection,
        matching: find.textContaining('Detected:'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detection, matching: find.textContaining('Today')),
      findsOneWidget,
    );
  });

  testWidgets('overview can browse future months and return to current month', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Go to current month'), findsOneWidget);

    await tester.tap(find.byTooltip('Go to current month'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Go to current month'), findsNothing);
  });

  testWidgets('all tasks confirms the impact before deleting a task', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);
    await addTaskFromAllTasks(tester, 'Delete me');

    await tester.tap(find.byTooltip('More actions for Delete me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete task'));
    await tester.pumpAndSettle();

    expect(find.text('Delete task?'), findsOneWidget);
    expect(find.textContaining('all of its scheduled dates'), findsOneWidget);
  });

  testWidgets('quick add smart tokens create a focused task for today', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await addTaskFromAllTasks(
      tester,
      'Nộp báo cáo hôm nay 9:30 !cao ~45p #laptop',
    );

    final prefs = await SharedPreferences.getInstance();
    final tasks = prefs.getString(TaskStore.tasksKeyFor('preview')) ?? '';
    final assignments =
        prefs.getString(TaskStore.assignmentsKeyFor('preview')) ?? '';
    expect(tasks, contains('Nộp báo cáo'));
    expect(tasks, contains('"priority":"high"'));
    expect(tasks, contains('"estimateMinutes":45'));
    expect(tasks, contains('"iconKind":"laptop"'));
    expect(assignments, contains('"reminderHour":9'));
    expect(assignments, contains('"reminderMinute":30'));
  });

  testWidgets('overview day opens editable task popup', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    await openTab(tester, 2);

    await addTaskFromAllTasks(tester, 'Kiểm tra lịch', scheduleToday: true);

    await openTab(tester, 0);

    final todayKey = ValueKey(
      'calendar-${DateTime.now().toIso8601String().substring(0, 10)}',
    );
    await tester.tap(find.byKey(todayKey));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Kiểm tra lịch'), findsOneWidget);
    expect(find.byTooltip('Task actions'), findsOneWidget);
  });

  testWidgets('overview preview hides future no priority and daily tasks', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = dateOnly(now);
    final tomorrow = today.add(const Duration(days: 1));
    final dailyTask = TaskItem(
      id: 'daily-task',
      title: 'Daily stretch',
      priority: TaskPriority.normal,
      createdAt: now,
      updatedAt: now,
    );
    final noPriorityTask = TaskItem(
      id: 'no-priority-task',
      title: 'Buy fruit',
      priority: TaskPriority.none,
      createdAt: now,
      updatedAt: now,
    );
    final priorityTask = TaskItem(
      id: 'priority-task',
      title: 'Pay invoice',
      priority: TaskPriority.high,
      createdAt: now,
      updatedAt: now,
    );
    final assignments = <TaskAssignment>[
      for (var index = 0; index < 30; index++)
        TaskAssignment(
          id: 'daily-$index',
          taskId: dailyTask.id,
          date: today.add(Duration(days: index)),
          createdAt: now,
          updatedAt: now,
        ),
      TaskAssignment(
        id: 'no-priority-today',
        taskId: noPriorityTask.id,
        date: today,
        createdAt: now,
        updatedAt: now,
      ),
      TaskAssignment(
        id: 'no-priority-tomorrow',
        taskId: noPriorityTask.id,
        date: tomorrow,
        createdAt: now,
        updatedAt: now,
      ),
      TaskAssignment(
        id: 'priority-tomorrow',
        taskId: priorityTask.id,
        date: tomorrow,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
      TaskStore.tasksKey: jsonEncode([
        dailyTask.toJson(),
        noPriorityTask.toJson(),
        priorityTask.toJson(),
      ]),
      TaskStore.assignmentsKey: jsonEncode([
        for (final assignment in assignments) assignment.toJson(),
      ]),
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    final todayKey = ValueKey(
      'calendar-${today.toIso8601String().substring(0, 10)}',
    );
    await tester.tap(find.byKey(todayKey));
    await tester.pumpAndSettle();
    expect(find.text('Daily stretch'), findsOneWidget);
    expect(find.text('Buy fruit'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    final tomorrowKey = ValueKey(
      'calendar-${tomorrow.toIso8601String().substring(0, 10)}',
    );
    await tester.tap(find.byKey(tomorrowKey));
    await tester.pumpAndSettle();

    expect(find.text('Pay invoice'), findsOneWidget);
    expect(find.text('Daily stretch'), findsNothing);
    expect(find.text('Buy fruit'), findsNothing);
  });

  testWidgets('main task views remain overflow-free at representative widths', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpWidget(const TaskReminderApp());
      await tester.pumpAndSettle();
      for (var tab = 0; tab < 4; tab++) {
        await openTab(tester, tab);
        expect(
          tester.takeException(),
          isNull,
          reason: 'viewport width $width, tab $tab',
        );
      }
    }
  });

  testWidgets(
    'task views and add dialog support large text and phone rotation',
    (tester) async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        AuthCache.userKey: 'preview',
        AuthCache.passwordKey: 'preview-password',
        TaskStore.tasksKeyFor('preview'): jsonEncode([
          TaskItem(
            id: 'long-task',
            title: 'Kiểm tra lịch hẹn và hoàn thành báo cáo quan trọng',
            note: 'Ghi chú dài để kiểm tra khả năng đọc trên điện thoại.',
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ]),
        TaskStore.assignmentsKeyFor('preview'): jsonEncode([
          TaskAssignment(
            id: 'long-schedule',
            taskId: 'long-task',
            date: now,
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ]),
      });
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(const TaskReminderApp());
        await tester.pumpAndSettle();
        for (var tab = 0; tab < 4; tab++) {
          await openTab(tester, tab);
          expect(
            tester.takeException(),
            isNull,
            reason: 'size $size, tab $tab',
          );
        }
        await openTab(tester, 2);
        await tester.scrollUntilVisible(
          find.byTooltip('Add task'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(WorkListPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.byTooltip('Add task'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'add dialog at $size');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('add task options stay stable at phone scale', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'preview',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'home');
    await openTab(tester, 2);
    expect(tester.takeException(), isNull, reason: 'all tasks');

    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final label in ['Icon', 'Priority', 'Schedule']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }

    expect(find.widgetWithText(ChoiceChip, '15m'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Every day'), findsOneWidget);
  });
}

Future<void> openTab(WidgetTester tester, int index) async {
  final nav = find.byType(NavigationBar);
  final topLeft = tester.getTopLeft(nav);
  final size = tester.getSize(nav);
  await tester.tapAt(
    Offset(
      topLeft.dx + size.width * (index + .5) / 4,
      topLeft.dy + size.height / 2,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> addTaskFromAllTasks(
  WidgetTester tester,
  String title, {
  bool scheduleToday = false,
}) async {
  await tester.tap(find.byTooltip('Add task'));
  await tester.pumpAndSettle();
  expect(find.widgetWithText(ActionChip, 'Today'), findsNothing);
  expect(find.widgetWithText(ActionChip, 'Tomorrow'), findsNothing);
  expect(find.widgetWithText(ActionChip, 'No schedule'), findsNothing);
  expect(find.byKey(const ValueKey('add-task-month-day-input')), findsNothing);
  expect(find.widgetWithText(OutlinedButton, 'More options'), findsNothing);
  await tester.enterText(
    find.byKey(const ValueKey('add-task-title-input')),
    title,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
  await tester.pumpAndSettle();
  if (scheduleToday) {
    final taskText = find.text(title).last;
    await tester.ensureVisible(taskText);
    await tester.pumpAndSettle();
    final addToday = find.byKey(ValueKey('add-today-${title.toLowerCase()}'));
    await tester.ensureVisible(addToday);
    await tester.pumpAndSettle();
    await tester.tap(addToday);
    await tester.pumpAndSettle();
  }
}
