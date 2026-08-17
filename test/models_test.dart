import 'package:flutter_test/flutter_test.dart';
import 'package:task_reminder/src/models.dart';

void main() {
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
}
