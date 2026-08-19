import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_reminder/src/models.dart';
import 'package:task_reminder/src/storage.dart';

void main() {
  test('keeps backend URL empty until the user chooses to sync', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await BackendConfig.loadUrl(), isEmpty);
  });

  test('deduplicates repeated task titles in the work library', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TaskStore.load();
    final now = DateTime.utc(2026, 8, 14);

    await store.saveTasks([]);
    await store.addTask(
      TaskItem(
        id: '1',
        title: '  Học Flutter ',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await store.addTask(
      TaskItem(id: '2', title: 'học   flutter', createdAt: now, updatedAt: now),
    );

    expect(store.tasks(), hasLength(1));
  });

  test('snoozes an assignment to a future reminder time', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TaskStore.load();
    final now = DateTime.now();

    await store.saveAssignments([
      TaskAssignment(
        id: 'assign-1',
        taskId: 'task-1',
        date: dateOnly(now),
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    await store.snoozeAssignment('assign-1', const Duration(minutes: 15));

    final assignment = store.assignments().single;
    expect(assignment.done, isFalse);
    expect(assignment.updatedAt.isAfter(now), isTrue);
    expect(assignment.reminderHour, inInclusiveRange(0, 23));
    expect(assignment.reminderMinute, inInclusiveRange(0, 59));
  });
}
