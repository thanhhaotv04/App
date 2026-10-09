import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'storage.dart';

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> backendRequest(
  String baseUrl,
  String path, {
  String method = 'GET',
  Map<String, Object?>? body,
  Map<String, String> headers = const {},
  http.Client? client,
}) async {
  final uri = BackendConfig.validateUrl(baseUrl).resolve(path);
  final connection = client ?? http.Client();
  try {
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await (() async {
      final streamed = await connection.send(request);
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        if (bytes.length + chunk.length > 8 * 1024 * 1024) {
          throw const FormatException('Backend response is too large.');
        }
        bytes.addAll(chunk);
      }
      return http.Response.bytes(bytes, streamed.statusCode);
    })().timeout(const Duration(seconds: 15));
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const FormatException(
        'Backend returned an invalid response. Please retry.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        data['message']?.toString() ??
            'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
        code: data['error']?.toString(),
      );
    }
    return data;
  } finally {
    if (client == null) connection.close();
  }
}

class AuthSession {
  const AuthSession({required this.name, required this.token});

  final String name;
  final String token;
}

class AuthService {
  const AuthService({required this.baseUrl, this.client});

  final String baseUrl;
  final http.Client? client;

  Future<AuthSession> signIn(String name, String password) async {
    final data = await _post('/api/auth/login', {
      'name': name,
      'password': password,
    }, fallback: 'Sign in failed');
    return _session(data, name);
  }

  Future<AuthSession> register(String name, String password) async {
    final data = await _post('/api/auth/register', {
      'name': name,
      'password': password,
    }, fallback: 'Register failed');
    return _session(data, name);
  }

  Future<void> resetPassword(String name, String newPassword) async {
    await _post('/api/auth/reset-password', {
      'name': name,
      'newPassword': newPassword,
    }, fallback: 'Password reset failed');
  }

  Future<AuthSession> updatePassword({
    required String name,
    required String currentPassword,
    required String newPassword,
    required String token,
  }) async {
    final data = await _post(
      '/api/auth/update',
      {
        'name': name,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      headers: {'Authorization': 'Bearer $token'},
      fallback: 'Password update failed',
    );
    return _session(data, name);
  }

  Future<void> logout(String token) async {
    if (token.trim().isEmpty) return;
    try {
      await _post(
        '/api/auth/logout',
        const {},
        headers: {'Authorization': 'Bearer ${token.trim()}'},
        fallback: 'Sign out failed',
      );
    } on AuthException catch (error) {
      // An expired or already revoked session needs no further revocation.
      if (error.statusCode != 401) rethrow;
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    required String fallback,
  }) async {
    return backendRequest(
      baseUrl,
      path,
      method: 'POST',
      body: body,
      headers: headers,
      client: client,
    );
  }

  AuthSession _session(Map<String, dynamic> data, String fallbackName) {
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw const AuthException('Backend did not return a secure session.');
    }
    return AuthSession(
      name: data['name']?.toString() ?? fallbackName,
      token: token,
    );
  }
}

class TaskSyncService {
  TaskSyncService({
    required this.baseUrl,
    required this.userName,
    required this.password,
    this.token = '',
    this.client,
  });

  final String baseUrl;
  final String userName;
  final String password;
  final String token;
  final http.Client? client;
  String? sessionToken;

  Future<TaskSyncData> syncTwoWay(
    List<TaskItem> localTasks,
    List<TaskAssignment> localAssignments,
  ) async {
    sessionToken = token.isEmpty ? await _loginOrRegister() : token;
    TaskSyncData remote;
    try {
      remote = await pullRemote(sessionToken!);
    } on AuthException catch (error) {
      if (error.statusCode != 401 || token.isEmpty) rethrow;
      // Exactly one renewal attempt; never retry a failed write blindly.
      sessionToken = await _loginOrRegister();
      remote = await pullRemote(sessionToken!);
    }
    final merged = mergeTaskData(
      TaskSyncData(localTasks, localAssignments),
      remote,
    );
    final response = await backendRequest(
      baseUrl,
      '/api/task-reminder/data',
      client: client,
      method: 'POST',
      headers: {'Authorization': 'Bearer ${sessionToken!}'},
      body: {
        'tasks': merged.tasks.map((item) => item.toJson()).toList(),
        'assignments': merged.assignments.map((item) => item.toJson()).toList(),
      },
    );
    return _decode(response);
  }

  Future<TaskSyncData> pullRemote(String activeToken) async => _decode(
    await backendRequest(
      baseUrl,
      '/api/task-reminder/data',
      client: client,
      headers: {'Authorization': 'Bearer $activeToken'},
    ),
  );

  TaskSyncData _decode(Map<String, dynamic> data) {
    if (data['tasks'] is! List || data['assignments'] is! List) {
      throw const FormatException(
        'Backend returned invalid task data. Local data was kept.',
      );
    }
    return TaskSyncData(
      (data['tasks'] as List)
          .map(
            (item) => TaskItem.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(),
      (data['assignments'] as List)
          .map(
            (item) =>
                TaskAssignment.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(),
    );
  }

  Future<String> _loginOrRegister() async {
    final auth = AuthService(baseUrl: baseUrl, client: client);
    try {
      return (await auth.signIn(userName, password)).token;
    } on AuthException catch (error) {
      if (error.code == 'invalid_credentials') {
        try {
          return (await auth.register(userName, password)).token;
        } on AuthException catch (registrationError) {
          if (registrationError.statusCode == 409) throw error;
          rethrow;
        }
      }
      rethrow;
    }
  }
}

class LocalReminderService {
  LocalReminderService._();

  static final instance = LocalReminderService._();
  static const enabledKey = 'task-reminder-notifications-enabled';
  static const showTitlesKey = 'task-reminder-notifications-show-titles';
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _available = true;
  Future<void>? _queue;

  Future<void> init() async {
    if (_initialized || kIsWeb || !_available) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
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
    final granted =
        await android?.requestNotificationsPermission() ??
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        await macos?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
    await (await SharedPreferences.getInstance()).setBool(enabledKey, granted);
    return granted;
  }

  Future<void> disable() => _enqueue(() async {
    await (await SharedPreferences.getInstance()).setBool(enabledKey, false);
    await init();
    if (_initialized && _available && !kIsWeb) await _plugin.cancelAll();
  });

  Future<void> reschedule({
    required List<TaskItem> tasks,
    required List<TaskAssignment> assignments,
  }) {
    return _enqueue(() => _reschedule(tasks: tasks, assignments: assignments));
  }

  Future<void> cancelAll() {
    return _enqueue(() async {
      if (_initialized && _available && !kIsWeb) await _plugin.cancelAll();
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = (_queue ?? Future<void>.value()).then((_) => action());
    final settled = operation.catchError((_) {});
    _queue = settled;
    return operation.whenComplete(() {
      if (identical(_queue, settled)) _queue = null;
    });
  }

  Future<void> _reschedule({
    required List<TaskItem> tasks,
    required List<TaskAssignment> assignments,
  }) async {
    await init();
    if (kIsWeb || !_available || !_initialized) return;
    await _plugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(enabledKey) != true) return;
    final showTitles = prefs.getBool(showTitlesKey) == true;
    final byId = {for (final task in tasks) task.id: task};
    final now = DateTime.now();
    final pending =
        assignments.where((item) => !item.done && !item.isDeleted).toList()
          ..sort((a, b) => reminderTimeFor(a).compareTo(reminderTimeFor(b)));
    var count = 0;
    for (final assignment in pending) {
      final task = byId[assignment.taskId];
      if (task == null || task.isDeleted) continue;
      if (task.priority == TaskPriority.none) continue;
      final scheduled = reminderTimeFor(assignment);
      if (!scheduled.isAfter(now)) continue;
      // Keep within iOS's pending-notification limit and avoid flooding alarms.
      if (++count > 64) break;
      await _plugin.zonedSchedule(
        stableNotificationId(assignment.id),
        'Task Reminder',
        showTitles ? task.title : 'A task is due. Open the app to view it.',
        tz.TZDateTime.from(scheduled, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_tasks',
            'Daily task reminders',
            channelDescription: 'Reminders for pending daily tasks',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

DateTime reminderTimeFor(TaskAssignment assignment) => DateTime(
  assignment.date.year,
  assignment.date.month,
  assignment.date.day,
  assignment.reminderHour,
  assignment.reminderMinute,
);

int stableNotificationId(String id) {
  final bytes = sha256.convert(utf8.encode(id)).bytes;
  return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
      0x7fffffff;
}

class UpdateInfo {
  const UpdateInfo({
    required this.available,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.notes,
    this.sha256Digest = '',
    this.size = 0,
  });

  final bool available;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String notes;
  final String sha256Digest;
  final int size;
}

class AppUpdateService {
  const AppUpdateService({
    required this.baseUrl,
    this.client,
    this.currentBuildNumber,
  });

  static const maxApkBytes = 200 * 1024 * 1024;
  static const _channel = MethodChannel('task_reminder/update');

  final String baseUrl;
  final http.Client? client;
  final int? currentBuildNumber;

  Future<UpdateInfo> checkLatest() async {
    final baseUri = BackendConfig.validateUrl(baseUrl);
    final data = await backendRequest(
      baseUrl,
      '/api/update/latest',
      client: client,
    );
    final remoteCode = (data['versionCode'] as num?)?.toInt() ?? 0;
    final apkPath = data['apkUrl']?.toString() ?? '';
    final apkUri = baseUri.resolve(apkPath);
    if (apkPath.isEmpty ||
        apkUri.userInfo.isNotEmpty ||
        apkUri.fragment.isNotEmpty ||
        apkUri.scheme != baseUri.scheme ||
        apkUri.host != baseUri.host ||
        apkUri.port != baseUri.port) {
      throw const FormatException('Backend returned an unsafe APK URL.');
    }
    final currentCode =
        currentBuildNumber ??
        int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ??
        0;
    return UpdateInfo(
      available: remoteCode > currentCode,
      versionName: data['versionName']?.toString() ?? '',
      versionCode: remoteCode,
      apkUrl: apkUri.toString(),
      notes: data['notes']?.toString() ?? '',
      sha256Digest: data['sha256']?.toString().toLowerCase() ?? '',
      size: (data['size'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String> downloadApk(UpdateInfo info) async {
    final base = BackendConfig.validateUrl(baseUrl);
    final uri = Uri.parse(info.apkUrl);
    if (uri.origin != base.origin ||
        uri.userInfo.isNotEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(info.sha256Digest) ||
        info.size <= 0 ||
        info.size > maxApkBytes) {
      throw const FormatException('Update metadata is incomplete or unsafe.');
    }
    final downloadClient = client ?? http.Client();
    Directory? dir;
    IOSink? sink;
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await downloadClient
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('APK download failed: ${response.statusCode}');
      }
      if (response.contentLength != null &&
          response.contentLength != info.size) {
        throw const FormatException(
          'APK size does not match the update manifest.',
        );
      }
      dir = await _downloadDir();
      final file = File('${dir.path}${Platform.pathSeparator}update.apk');
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > info.size || received > maxApkBytes) {
          throw const FormatException(
            'Downloaded APK is larger than expected.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != info.size ||
          (await sha256.bind(file.openRead()).first).toString() !=
              info.sha256Digest) {
        throw const FormatException('Downloaded APK failed integrity check.');
      }
      return file.path;
    } catch (_) {
      await sink?.close();
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    } finally {
      if (client == null) downloadClient.close();
    }
  }

  Future<void> installApk(String path) async {
    if (!Platform.isAndroid) {
      throw Exception('APK install is only available on Android.');
    }
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }

  Future<Directory> _downloadDir() async {
    final base = Platform.isAndroid
        ? await getTemporaryDirectory()
        : Directory.systemTemp;
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    return dir.createTemp('verified-');
  }
}
