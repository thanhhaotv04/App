import 'package:flutter/material.dart';

enum TaskPriority { low, normal, high }

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
  });

  final String id;
  final String title;
  final String note;
  final TaskPriority priority;
  final TaskIconKind iconKind;
  final int estimateMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskItem copyWith({
    String? title,
    String? note,
    TaskPriority? priority,
    TaskIconKind? iconKind,
    int? estimateMinutes,
    DateTime? updatedAt,
  }) => TaskItem(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    priority: priority ?? this.priority,
    iconKind: iconKind ?? this.iconKind,
    estimateMinutes: estimateMinutes ?? this.estimateMinutes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'priority': priority.name,
    'iconKind': iconKind.name,
    'estimateMinutes': estimateMinutes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
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
  });

  final String id;
  final String taskId;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int reminderHour;
  final int reminderMinute;
  final DateTime? completedAt;

  bool get done => completedAt != null;

  TaskAssignment copyWith({
    DateTime? date,
    DateTime? updatedAt,
    int? reminderHour,
    int? reminderMinute,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) => TaskAssignment(
    id: id,
    taskId: taskId,
    date: date ?? this.date,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'taskId': taskId,
    'date': dateOnly(date).toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'completedAt': completedAt?.toIso8601String(),
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
    );
  }
}

@immutable
class TaskSyncData {
  const TaskSyncData(this.tasks, this.assignments);

  final List<TaskItem> tasks;
  final List<TaskAssignment> assignments;
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String normalizedTaskTitle(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
