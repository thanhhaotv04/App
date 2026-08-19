import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:task_reminder/src/app.dart';
import 'package:task_reminder/src/storage.dart';

void main() {
  setUp(() {
    TaskReminderApp.themeMode.value = ThemeMode.light;
  });

  testWidgets('shows the task reminder sign-in screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Backend URL'), findsNothing);
  });

  testWidgets('can sign in offline without backend URL', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'offline-user');
    await tester.enterText(find.byType(TextField).at(1), 'offline-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthCache.userKey), 'offline-user');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

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
    expect(prefs.getString(TaskStore.tasksKey), contains('Viết báo cáo'));
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
    expect(prefs.getString(TaskStore.tasksKey), contains('Gọi điện cho mẹ'));
    expect(prefs.getString(TaskStore.assignmentsKey), contains('taskId'));
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'More options'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);

    final monChip = find.widgetWithText(ActionChip, 'Mon');
    await tester.ensureVisible(monChip);
    await tester.pumpAndSettle();
    await tester.tap(monChip);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final assignments = prefs.getString(TaskStore.assignmentsKey) ?? '';
    expect(assignments, contains('taskId'));
    expect(
      RegExp('Lịch tuần').hasMatch(prefs.getString(TaskStore.tasksKey) ?? ''),
      isTrue,
    );
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
    await openTab(tester, 2);

    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-task-title-input')),
      'Pay bills',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'More options'));
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
        jsonDecode(prefs.getString(TaskStore.assignmentsKey) ?? '[]')
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'No priority'));
    await tester.pumpAndSettle();
    expect(find.text('Anytime today'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TaskStore.tasksKey), contains('"priority":"none"'));
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Travel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(TaskStore.tasksKey),
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'More options'));
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
    final tasks = prefs.getString(TaskStore.tasksKey) ?? '';
    expect(tasks, contains('Task mới'));
    expect(tasks, contains('Ghi chú mới'));
  });

  testWidgets('daily moves a task to collapsible done after double tap', (
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

    await tester.tap(find.text('Uống nước'));
    await tester.pumpAndSettle();
    expect(find.text('Uống nước'), findsOneWidget);

    await tester.tap(find.text('Uống nước'));
    await tester.tap(find.text('Uống nước'));
    await tester.pumpAndSettle();
    expect(find.text('Uống nước'), findsNothing);

    await tester.tap(find.byTooltip('Expand Done'));
    await tester.pumpAndSettle();
    expect(find.text('Uống nước'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Uống nước'), findsOneWidget);
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
    final tasks = prefs.getString(TaskStore.tasksKey) ?? '';
    final assignments = prefs.getString(TaskStore.assignmentsKey) ?? '';
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

  testWidgets('today view remains overflow-free at representative widths', (
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
      expect(tester.takeException(), isNull, reason: 'viewport width $width');
    }
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
  expect(find.widgetWithText(OutlinedButton, 'More options'), findsOneWidget);
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
