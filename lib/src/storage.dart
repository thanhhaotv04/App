import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class BackendConfig {
  static const defaultUrl = '';
  static const exampleUrl = 'http://192.168.1.142:3002';
  static const legacyDefaultUrl = 'http://127.0.0.1:3000';
  static const key = 'task-reminder-backend-url';

  static Future<String> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key)?.trim();
    if (value == null || value.isEmpty || value == legacyDefaultUrl) {
      return defaultUrl;
    }
    return value;
  }

  static Future<void> saveUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(key, normalized);
  }
}

class AuthCache {
  static const userKey = 'task-reminder-auth-user';
  static const passwordKey = 'task-reminder-auth-password';

  static Future<(String, String)?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(userKey);
    final password = prefs.getString(passwordKey);
    if (user == null || user.isEmpty || password == null || password.isEmpty) {
      return null;
    }
    return (user, password);
  }

  static Future<void> save(String user, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userKey, user);
    await prefs.setString(passwordKey, password);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(userKey);
    await prefs.remove(passwordKey);
  }
}

class TaskStore {
  TaskStore._(this._prefs);

  static const tasksKey = 'task-reminder-tasks-v1';
  static const assignmentsKey = 'task-reminder-assignments-v1';

  final SharedPreferences _prefs;

  static Future<TaskStore> load() async =>
      TaskStore._(await SharedPreferences.getInstance());

  List<TaskItem> tasks() {
    final raw = _prefs.getString(tasksKey);
    if (raw == null || raw.isEmpty) return _seedTasks();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded
          .map(
            (item) => TaskItem.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList();
      items.sort((a, b) => a.title.compareTo(b.title));
      return _dedupeTasks(items);
    } catch (_) {
      return _seedTasks();
    }
  }

  List<TaskAssignment> assignments() {
    final raw = _prefs.getString(assignmentsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded
          .map(
            (item) =>
                TaskAssignment.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList();
      items.sort((a, b) => a.date.compareTo(b.date));
      return items;
    } catch (_) {
      return [];
    }
  }

  List<TaskAssignment> assignmentsFor(DateTime date) =>
      assignments()
          .where((item) => isSameDay(item.date, dateOnly(date)))
          .toList()
        ..sort((a, b) {
          if (a.done != b.done) return a.done ? 1 : -1;
          return a.createdAt.compareTo(b.createdAt);
        });

  Future<void> saveTasks(List<TaskItem> items) async {
    final deduped = _dedupeTasks(items)
      ..sort((a, b) => a.title.compareTo(b.title));
    await _prefs.setString(
      tasksKey,
      jsonEncode(deduped.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> saveAssignments(List<TaskAssignment> items) async {
    final sorted = [...items]..sort((a, b) => a.date.compareTo(b.date));
    await _prefs.setString(
      assignmentsKey,
      jsonEncode(sorted.map((item) => item.toJson()).toList()),
    );
  }

  Future<TaskItem> addTask(TaskItem task) async {
    final items = tasks();
    final key = normalizedTaskTitle(task.title);
    final existing = items.where(
      (item) => normalizedTaskTitle(item.title) == key,
    );
    if (existing.isNotEmpty) return existing.first;
    items.add(task);
    await saveTasks(items);
    return task;
  }

  Future<void> addAssignment(TaskAssignment assignment) async {
    final items = assignments();
    final exists = items.any(
      (item) =>
          item.taskId == assignment.taskId &&
          isSameDay(item.date, assignment.date),
    );
    if (!exists) {
      items.add(assignment);
      await saveAssignments(items);
    }
  }

  Future<void> updateTask(TaskItem task) async {
    final items = tasks()
        .map((item) => item.id == task.id ? task : item)
        .toList();
    await saveTasks(items);
  }

  Future<void> removeTask(String taskId) async {
    final taskItems = tasks()..removeWhere((item) => item.id == taskId);
    final assignmentItems = assignments()
      ..removeWhere((item) => item.taskId == taskId);
    await saveTasks(taskItems);
    await saveAssignments(assignmentItems);
  }

  Future<void> updateAssignment(TaskAssignment assignment) async {
    final items = assignments()
        .map((item) => item.id == assignment.id ? assignment : item)
        .toList();
    await saveAssignments(items);
  }

  Future<void> markDone(String assignmentId) async {
    final now = DateTime.now();
    final items = assignments()
        .map(
          (item) => item.id == assignmentId
              ? item.copyWith(completedAt: now, updatedAt: now)
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> unmarkDone(String assignmentId) async {
    final now = DateTime.now();
    final items = assignments()
        .map(
          (item) => item.id == assignmentId
              ? item.copyWith(updatedAt: now, clearCompletedAt: true)
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> markAllDoneFor(DateTime date) async {
    final now = DateTime.now();
    final items = assignments()
        .map(
          (item) => isSameDay(item.date, date) && !item.done
              ? item.copyWith(completedAt: now, updatedAt: now)
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> moveAssignment(String assignmentId, DateTime date) async {
    final now = DateTime.now();
    final items = assignments()
        .map(
          (item) => item.id == assignmentId
              ? item.copyWith(
                  date: dateOnly(date),
                  updatedAt: now,
                  clearCompletedAt: true,
                )
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> snoozeAssignment(String assignmentId, Duration offset) async {
    final now = DateTime.now();
    final next = now.add(offset);
    final items = assignments()
        .map(
          (item) => item.id == assignmentId
              ? item.copyWith(
                  date: dateOnly(next),
                  reminderHour: next.hour,
                  reminderMinute: next.minute,
                  updatedAt: now,
                  clearCompletedAt: true,
                )
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> removeAssignment(String assignmentId) async {
    final items = assignments()..removeWhere((item) => item.id == assignmentId);
    await saveAssignments(items);
  }

  Future<void> replaceAll(TaskSyncData data) async {
    await saveTasks([...data.tasks]);
    await saveAssignments([...data.assignments]);
  }

  List<TaskItem> _dedupeTasks(List<TaskItem> items) {
    final byTitle = <String, TaskItem>{};
    for (final item in items) {
      final key = normalizedTaskTitle(item.title);
      final previous = byTitle[key];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        byTitle[key] = item;
      }
    }
    return byTitle.values.toList();
  }

  List<TaskItem> _seedTasks() {
    final now = DateTime.now();
    return [
      TaskItem(
        id: 'seed-1',
        title: 'Read embedded notes',
        note: 'Review yesterday notes',
        createdAt: now,
        updatedAt: now,
      ),
      TaskItem(
        id: 'seed-2',
        title: 'Exercise',
        note: 'Keep the routine going',
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }
}
