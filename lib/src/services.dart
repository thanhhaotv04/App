import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  const AuthService({required this.baseUrl});

  final String baseUrl;

  Future<String> signIn(String name, String password) async {
    final data = await _post('/api/auth/login', {
      'name': name,
      'password': password,
    }, fallback: 'Sign in failed');
    return data['name']?.toString() ?? name;
  }

  Future<String> register(String name, String password) async {
    final data = await _post('/api/auth/register', {
      'name': name,
      'password': password,
    }, fallback: 'Register failed');
    return data['name']?.toString() ?? name;
  }

  Future<void> resetPassword(String name, String newPassword) async {
    await _post('/api/auth/reset-password', {
      'name': name,
      'newPassword': newPassword,
    }, fallback: 'Password reset failed');
  }

  Future<String> updatePassword({
    required String name,
    required String currentPassword,
    required String newPassword,
  }) async {
    final data = await _post(
      '/api/auth/update',
      {
        'name': name,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      headers: {'X-Password': currentPassword},
      fallback: 'Password update failed',
    );
    return data['name']?.toString() ?? name;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    required String fallback,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json', ...headers},
      body: jsonEncode(body),
    );
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        data['message']?.toString() ??
            data['error']?.toString() ??
            '$fallback: ${response.statusCode}',
      );
    }
    return data;
  }
}

class TaskSyncService {
  const TaskSyncService({
    required this.baseUrl,
    required this.userName,
    required this.password,
  });

  final String baseUrl;
  final String userName;
  final String password;

  Map<String, String> get _authHeaders => {
    'X-User-Name': userName,
    'X-Password': password,
  };

  Future<TaskSyncData> syncTwoWay(
    List<TaskItem> localTasks,
    List<TaskAssignment> localAssignments,
  ) async {
    await _ensureBackendAccount();
    final remote = await pullRemote();
    final tasks = _mergeTasks(localTasks, remote.tasks);
    final assignments = _mergeAssignments(localAssignments, remote.assignments);
    await _saveRemote(tasks, assignments);
    return TaskSyncData(tasks, assignments);
  }

  Future<TaskSyncData> pullRemote() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/task-reminder/data'),
      headers: _authHeaders,
    );
    if (response.statusCode == 401) {
      throw const AuthException(
        'Backend rejected this account. Sign in again or reset the password.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Load failed: ${response.statusCode}');
    }
    final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final tasksJson = data['tasks'] as List? ?? const [];
    final assignmentJson = data['assignments'] as List? ?? const [];
    return TaskSyncData(
      tasksJson
          .map(
            (item) => TaskItem.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(),
      assignmentJson
          .map(
            (item) =>
                TaskAssignment.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(),
    );
  }

  Future<void> _saveRemote(
    List<TaskItem> tasks,
    List<TaskAssignment> assignments,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/task-reminder/data'),
      headers: {'Content-Type': 'application/json', ..._authHeaders},
      body: jsonEncode({
        'tasks': tasks.map((item) => item.toJson()).toList(),
        'assignments': assignments.map((item) => item.toJson()).toList(),
      }),
    );
    if (response.statusCode == 401) {
      throw const AuthException(
        'Backend rejected this account. Sign in again or reset the password.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Save failed: ${response.statusCode}');
    }
  }

  List<TaskItem> _mergeTasks(List<TaskItem> local, List<TaskItem> remote) {
    final byId = <String, TaskItem>{for (final item in local) item.id: item};
    for (final item in remote) {
      final previous = byId[item.id];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        byId[item.id] = item;
      }
    }
    final byTitle = <String, TaskItem>{};
    for (final item in byId.values) {
      final key = normalizedTaskTitle(item.title);
      final previous = byTitle[key];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        byTitle[key] = item;
      }
    }
    return byTitle.values.toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  List<TaskAssignment> _mergeAssignments(
    List<TaskAssignment> local,
    List<TaskAssignment> remote,
  ) {
    final byId = <String, TaskAssignment>{
      for (final item in local) item.id: item,
    };
    for (final item in remote) {
      final previous = byId[item.id];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        byId[item.id] = item;
      }
    }
    return byId.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> _ensureBackendAccount() async {
    final auth = AuthService(baseUrl: baseUrl);
    try {
      await auth.signIn(userName, password);
    } on AuthException catch (error) {
      if (error.message == 'Account not found. Please register first.' ||
          error.message == 'Account not found.') {
        await auth.register(userName, password);
        return;
      }
      if (error.message.toLowerCase().contains('incorrect password')) {
        throw const AuthException(
          'Backend password is different. Sign out, then sign in with the '
          'backend password or reset it.',
        );
      }
      rethrow;
    }
  }
}

class LocalReminderService {
  LocalReminderService._();

  static final instance = LocalReminderService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _available = true;

  Future<void> init() async {
    if (_initialized || kIsWeb || !_available) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );
    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      _available = false;
    }
  }

  Future<bool> requestPermission() async {
    await init();
    if (kIsWeb || !_available) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ??
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        await macos?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;
  }

  Future<void> reschedule({
    required List<TaskItem> tasks,
    required List<TaskAssignment> assignments,
  }) async {
    await init();
    if (kIsWeb || !_available || !_initialized) return;
    await _plugin.cancelAll();
    final byId = {for (final task in tasks) task.id: task};
    final now = DateTime.now();
    for (final assignment in assignments.where((item) => !item.done)) {
      final task = byId[assignment.taskId];
      if (task == null) continue;
      var scheduled = DateTime(
        assignment.date.year,
        assignment.date.month,
        assignment.date.day,
        assignment.reminderHour.clamp(0, 23),
        assignment.reminderMinute.clamp(0, 59),
      );
      if (!scheduled.isAfter(now)) {
        if (isSameDay(assignment.date, now)) {
          scheduled = now.add(const Duration(minutes: 1));
        } else {
          continue;
        }
      }
      await _plugin.zonedSchedule(
        assignment.id.hashCode & 0x7fffffff,
        'Today reminder',
        task.title,
        tz.TZDateTime.from(scheduled, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_tasks',
            'Daily task reminders',
            channelDescription: 'Reminders for pending daily tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.available,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.notes,
  });

  final bool available;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String notes;
}

class AppUpdateService {
  const AppUpdateService({required this.baseUrl});

  static const currentVersionName = '1.0.0';
  static const currentVersionCode = 1;
  static const _channel = MethodChannel('task_reminder/update');

  final String baseUrl;

  Future<UpdateInfo> checkLatest() async {
    final response = await http.get(Uri.parse('$baseUrl/api/update/latest'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Update check failed: ${response.statusCode}');
    }
    final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final remoteCode = (data['versionCode'] as num?)?.toInt() ?? 0;
    final apkPath = data['apkUrl']?.toString() ?? '';
    return UpdateInfo(
      available: remoteCode > currentVersionCode,
      versionName: data['versionName']?.toString() ?? '',
      versionCode: remoteCode,
      apkUrl: apkPath.startsWith('http') ? apkPath : '$baseUrl$apkPath',
      notes: data['notes']?.toString() ?? '',
    );
  }

  Future<String> downloadApk(UpdateInfo info) async {
    final response = await http.get(Uri.parse(info.apkUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('APK download failed: ${response.statusCode}');
    }
    final dir = await _downloadDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}task-reminder-${info.versionCode}.apk',
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<void> installApk(String path) async {
    if (!Platform.isAndroid) {
      throw Exception('APK install is only available on Android.');
    }
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }

  Future<Directory> _downloadDir() async {
    final base = Platform.isAndroid
        ? Directory('/data/user/0/com.thanhhao.task_reminder/cache')
        : Directory.systemTemp;
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    return dir;
  }
}
