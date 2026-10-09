import 'package:flutter_test/flutter_test.dart';
import 'package:task_reminder/src/models.dart';

void main() {
  test(
    'sync timestamps use UTC while schedule dates remain calendar dates',
    () {
      final local = DateTime(2026, 9, 23, 9);
      final task = TaskItem(
        id: 'utc',
        title: 'UTC',
        createdAt: local,
        updatedAt: local,
      );
      final schedule = TaskAssignment(
        id: 'a',
        taskId: task.id,
        date: local,
        createdAt: local,
        updatedAt: local,
        completedAt: local,
      );
      expect(task.toJson()['updatedAt'], local.toUtc().toIso8601String());
      expect(task.toJson()['updatedAt'], endsWith('Z'));
      expect(schedule.toJson()['completedAt'], endsWith('Z'));
      expect(schedule.toJson()['date'], '2026-09-23T00:00:00.000');
    },
  );
  test(
    'stale devices cannot resurrect deleted parents or drop unrelated tasks',
    () {
      final now = DateTime.utc(2026, 9, 22);
      final task = TaskItem(
        id: '1',
        title: 'Task',
        createdAt: now,
        updatedAt: now,
      );
      final other = TaskItem(
        id: '2',
        title: 'Task',
        createdAt: now,
        updatedAt: now,
      );
      final assignment = TaskAssignment(
        id: 'a',
        taskId: '1',
        date: now,
        createdAt: now,
        updatedAt: now,
      );
      final merged = mergeTaskData(
        TaskSyncData([task.copyWith(deletedAt: now)], []),
        TaskSyncData(
          [task.copyWith(updatedAt: now.add(const Duration(days: 1))), other],
          [assignment],
        ),
      );
      expect(merged.tasks, hasLength(2));
      expect(merged.tasks.firstWhere((t) => t.id == '1').isDeleted, isTrue);
      expect(merged.assignments.single.isDeleted, isTrue);
    },
  );
  test('task JSON keeps stable id and timestamps', () {
    final original = TaskItem(
      id: 'task-1',
      title: 'Đọc tài liệu',
      note: 'Embedded Linux',
      priority: TaskPriority.high,
      iconKind: TaskIconKind.laptop,
      estimateMinutes: 45,
      createdAt: DateTime.utc(2026, 8, 14, 7),
      updatedAt: DateTime.utc(2026, 8, 14, 8),
    );

    final restored = TaskItem.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.priority, TaskPriority.high);
    expect(restored.iconKind, TaskIconKind.laptop);
    expect(restored.estimateMinutes, 45);
    expect(restored.updatedAt, original.updatedAt);
  });

  test('task JSON supports no priority tasks', () {
    final original = TaskItem(
      id: 'task-2',
      title: 'Clean inbox',
      priority: TaskPriority.none,
      createdAt: DateTime.utc(2026, 8, 14, 7),
      updatedAt: DateTime.utc(2026, 8, 14, 8),
    );

    final restored = TaskItem.fromJson(original.toJson());

    expect(restored.priority, TaskPriority.none);
  });

  test('assignment JSON stores date-only schedule and done state', () {
    final original = TaskAssignment(
      id: 'assign-1',
      taskId: 'task-1',
      date: DateTime.utc(2026, 8, 14, 17, 30),
      createdAt: DateTime.utc(2026, 8, 13),
      updatedAt: DateTime.utc(2026, 8, 14),
      reminderHour: 14,
      reminderMinute: 45,
      completedAt: DateTime.utc(2026, 8, 14, 9),
    );

    final restored = TaskAssignment.fromJson(original.toJson());

    expect(restored.date.hour, 0);
    expect(restored.reminderHour, 14);
    expect(restored.reminderMinute, 45);
    expect(restored.done, isTrue);
    expect(restored.completedAt, original.completedAt);
  });

  test('task and assignment JSON preserve deletion tombstones', () {
    final now = DateTime.utc(2026, 9, 22);
    final task = TaskItem(
      id: 'task-deleted',
      title: 'Removed task',
      createdAt: now,
      updatedAt: now,
      deletedAt: now,
    );
    final assignment = TaskAssignment(
      id: 'assignment-deleted',
      taskId: task.id,
      date: now,
      createdAt: now,
      updatedAt: now,
      deletedAt: now,
    );

    expect(TaskItem.fromJson(task.toJson()).isDeleted, isTrue);
    expect(TaskAssignment.fromJson(assignment.toJson()).isDeleted, isTrue);
  });
}
