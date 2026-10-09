import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_reminder/src/models.dart';
import 'package:task_reminder/src/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reminders require opt-in, skip past/done/deleted tasks and keep stable IDs',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'initialize' ||
                    call.method == 'requestNotificationsPermission'
                ? true
                : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final now = DateTime.now();
      final task = TaskItem(
        id: 'task',
        title: 'Reminder',
        createdAt: now,
        updatedAt: now,
      );
      TaskAssignment assignment(String id, DateTime date) => TaskAssignment(
        id: id,
        taskId: task.id,
        date: date,
        createdAt: now,
        updatedAt: now,
      );
      final future = assignment('future', now.add(const Duration(days: 2)));
      final items = [
        future,
        assignment('past', now.subtract(const Duration(days: 1))),
        assignment(
          'done',
          now.add(const Duration(days: 2)),
        ).copyWith(completedAt: now),
        assignment(
          'deleted',
          now.add(const Duration(days: 2)),
        ).copyWith(deletedAt: now),
      ];
      final reminders = LocalReminderService.instance;
      await reminders.reschedule(tasks: [task], assignments: items);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      expect(await reminders.requestPermission(), isTrue);
      await reminders.reschedule(tasks: [task], assignments: items);
      final scheduled = calls
          .where((c) => c.method == 'zonedSchedule')
          .toList();
      expect(scheduled, hasLength(1));
      expect(scheduled.single.arguments['id'], stableNotificationId('future'));
      expect(
        scheduled.single.arguments['body'],
        'A task is due. Open the app to view it.',
      );
      expect(
        scheduled.single.arguments['platformSpecifics']['visibility'],
        NotificationVisibility.private.index,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(LocalReminderService.showTitlesKey, true);
      calls.clear();
      await reminders.reschedule(tasks: [task], assignments: [future]);
      expect(
        calls.singleWhere((c) => c.method == 'zonedSchedule').arguments['body'],
        task.title,
      );
      calls.clear();
      await reminders.reschedule(
        tasks: [task.copyWith(deletedAt: now)],
        assignments: [future],
      );
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      await reminders.cancelAll();
      expect(calls.last.method, 'cancelAll');
      calls.clear();
      await reminders.reschedule(
        tasks: [task],
        assignments: List.generate(
          80,
          (i) => assignment('future-$i', now.add(Duration(days: i + 2))),
        ),
      );
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(64));
      await reminders.disable();
      expect(prefs.getBool(LocalReminderService.enabledKey), isFalse);
      expect(calls.last.method, 'cancelAll');
      calls.clear();
      await reminders.reschedule(tasks: [task], assignments: [future]);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    },
  );
}
