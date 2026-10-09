import 'package:flutter/material.dart';

enum TaskPriority { none, low, normal, high }

enum TaskIconKind { study, fitness, health, laptop, smile, travel }

@immutable
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.note = '',
    this.priority = TaskPriority.normal,
    this.iconKind = TaskIconKind.study,
    this.estimateMinutes = 15,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String note;
  final TaskPriority priority;
  final TaskIconKind iconKind;
  final int estimateMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  TaskItem copyWith({
    String? title,
    String? note,
    TaskPriority? priority,
    TaskIconKind? iconKind,
    int? estimateMinutes,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => TaskItem(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    priority: priority ?? this.priority,
    iconKind: iconKind ?? this.iconKind,
    estimateMinutes: estimateMinutes ?? this.estimateMinutes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'priority': priority.name,
    'iconKind': iconKind.name,
    'estimateMinutes': estimateMinutes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory TaskItem.fromJson(Map<String, Object?> json) {
    final created = DateTime.parse(json['createdAt'] as String);
    return TaskItem(
      id: json['id'] as String,
      title: json['title'] as String,
      note: json['note'] as String? ?? '',
      priority: TaskPriority.values.firstWhere(
        (item) => item.name == json['priority'],
        orElse: () => TaskPriority.normal,
      ),
      iconKind: TaskIconKind.values.firstWhere(
        (item) => item.name == json['iconKind'],
        orElse: () => TaskIconKind.study,
      ),
      estimateMinutes: (json['estimateMinutes'] as num?)?.toInt() ?? 15,
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? created,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
    );
  }
}

@immutable
class TaskAssignment {
  const TaskAssignment({
    required this.id,
    required this.taskId,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.reminderHour = 8,
    this.reminderMinute = 0,
    this.completedAt,
    this.deletedAt,
  });

  final String id;
  final String taskId;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int reminderHour;
  final int reminderMinute;
  final DateTime? completedAt;
  final DateTime? deletedAt;

  bool get done => completedAt != null;
  bool get isDeleted => deletedAt != null;

  TaskAssignment copyWith({
    DateTime? date,
    DateTime? updatedAt,
    int? reminderHour,
    int? reminderMinute,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => TaskAssignment(
    id: id,
    taskId: taskId,
    date: date ?? this.date,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'taskId': taskId,
    'date': dateOnly(date).toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory TaskAssignment.fromJson(Map<String, Object?> json) {
    final created = DateTime.parse(json['createdAt'] as String);
    return TaskAssignment(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      date: dateOnly(DateTime.parse(json['date'] as String)),
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? created,
      reminderHour: (json['reminderHour'] as num?)?.toInt() ?? 8,
      reminderMinute: (json['reminderMinute'] as num?)?.toInt() ?? 0,
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
    );
  }
}

@immutable
class TaskSyncData {
  const TaskSyncData(this.tasks, this.assignments);

  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
}

/// Merge stable IDs, preserving deletion records and newer local edits.
TaskSyncData mergeTaskData(TaskSyncData local, TaskSyncData remote) {
  final tasks = {for (final item in local.tasks) item.id: item};
  for (final item in remote.tasks) {
    final previous = tasks[item.id];
    if (previous == null ||
        (!previous.isDeleted && item.isDeleted) ||
        (previous.isDeleted == item.isDeleted &&
            item.updatedAt.isAfter(previous.updatedAt))) {
      tasks[item.id] = item;
    }
  }
  final assignments = {for (final item in local.assignments) item.id: item};
  for (final item in remote.assignments) {
    final previous = assignments[item.id];
    if (previous == null ||
        item.updatedAt.isAfter(previous.updatedAt) ||
        (item.updatedAt == previous.updatedAt && item.isDeleted)) {
      assignments[item.id] = item;
    }
  }
  for (final item in assignments.values.toList()) {
    final parent = tasks[item.taskId];
    if (parent?.isDeleted == true && !item.isDeleted) {
      assignments[item.id] = item.copyWith(
        deletedAt: parent!.deletedAt,
        updatedAt: parent.updatedAt,
      );
    }
  }
  return TaskSyncData(tasks.values.toList(), assignments.values.toList());
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String normalizedTaskTitle(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
