import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class BackendConfig {
  static const defaultUrl = '';
  static const exampleUrl = 'https://sync.example.com';
  static const legacyDefaultUrl = 'http://127.0.0.1:3000';
  static const key = 'task-reminder-backend-url';

  static Uri validateUrl(String value) {
    final uri = Uri.tryParse(value.trim().replaceAll(RegExp(r'/+$'), ''));
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path.isNotEmpty) {
      throw const FormatException(
        'Enter a backend origin such as https://example.com:3002 (no path or credentials).',
      );
    }
    final octets = uri.host.split('.').map(int.tryParse).toList();
    final loopbackIp =
        octets.length == 4 &&
        octets.every((n) => n != null && n >= 0 && n <= 255) &&
        octets[0] == 127;
    final loopback = uri.host == 'localhost' || uri.host == '::1' || loopbackIp;
    final desktopDevelopment =
        !kIsWeb &&
        const {
          TargetPlatform.linux,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        }.contains(defaultTargetPlatform);
    if (uri.scheme == 'http' && !(loopback && (kIsWeb || desktopDevelopment))) {
      throw const FormatException(
        'Backend connections must use HTTPS. HTTP is allowed only for localhost development on web and desktop.',
      );
    }
    return uri;
  }

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
    if (normalized.isEmpty) {
      await prefs.remove(key);
      return;
    }
    validateUrl(normalized);
    await prefs.setString(key, normalized);
  }
}

class AuthCache {
  static const userKey = 'task-reminder-auth-user';
  static const passwordKey = 'task-reminder-auth-password';
  static const _passwordSecureKey = 'task-reminder-auth-password-secure';
  static const _passwordFallbackKey = 'task-reminder-auth-password-fallback';
  static const _tokenSecureKey = 'task-reminder-auth-token';
  static const _pendingRevocationsSecureKey =
      'task-reminder-auth-pending-revocations';
  static const _tokenFallbackKey = 'task-reminder-auth-token-fallback';
  static const _verifierPrefix = 'task-reminder-auth-verifier-v2:';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static Future<(String, String)?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(userKey)?.trim() ?? '';
    await prefs.remove(_passwordFallbackKey);
    await prefs.remove(_tokenFallbackKey);
    if (!prefs.containsKey(TaskStore.legacyOwnerKey)) {
      await prefs.setString(TaskStore.legacyOwnerKey, user.toLowerCase());
    }
    if (user.isEmpty) {
      await prefs.remove(passwordKey);
      return null;
    }

    var password = await _readSecret(_passwordSecureKey, _passwordFallbackKey);
    final legacyPassword = prefs.getString(passwordKey) ?? '';
    if (password.isEmpty && legacyPassword.isNotEmpty) {
      password = legacyPassword;
      await _saveVerifierIfMissing(prefs, user, password);
      await _writeSecret(_passwordSecureKey, _passwordFallbackKey, password);
      await prefs.remove(passwordKey);
    }
    if (password.isEmpty) return null;
    // A previous interrupted migration may have left both copies behind.
    await prefs.remove(passwordKey);
    await _saveVerifierIfMissing(prefs, user, password);
    final verifier = prefs.getString(_verifierKey(user))!;
    if (!await _matchesVerifier(password, verifier)) {
      return null;
    }
    if (_needsRehash(verifier)) {
      await prefs.setString(_verifierKey(user), await _newVerifier(password));
    }
    return (user, password);
  }

  static Future<String?> signIn(String user, String password) async {
    final name = user.trim();
    final validation = validateCredentials(name, password, existing: true);
    if (validation != null) return validation;
    final prefs = await SharedPreferences.getInstance();
    final verifier = prefs.getString(_verifierKey(name));
    if (verifier == null || verifier.isEmpty) {
      final legacyUser = prefs.getString(userKey)?.trim() ?? '';
      final legacyPassword = prefs.getString(passwordKey) ?? '';
      if (!_sameUser(legacyUser, name) || legacyPassword != password) {
        return 'Account not found. Choose Create account first.';
      }
      await prefs.setString(_verifierKey(name), await _newVerifier(password));
      await prefs.remove(passwordKey);
    } else if (!await _matchesVerifier(password, verifier)) {
      return 'Incorrect password. Please try again.';
    } else if (_needsRehash(verifier)) {
      await prefs.setString(_verifierKey(name), await _newVerifier(password));
    }
    await _saveSession(name, password);
    return null;
  }

  static Future<String?> register(String user, String password) async {
    final name = user.trim();
    final validation = validateCredentials(name, password);
    if (validation != null) return validation;
    final prefs = await SharedPreferences.getInstance();
    final verifierKey = _verifierKey(name);
    if ((prefs.getString(verifierKey)?.isNotEmpty ?? false) ||
        (_sameUser(prefs.getString(userKey) ?? '', name) &&
            (prefs.getString(passwordKey)?.isNotEmpty ?? false))) {
      return 'This username already exists on this device.';
    }
    await prefs.setString(verifierKey, await _newVerifier(password));
    await _saveSession(name, password);
    return null;
  }

  static Future<void> updatePassword(String user, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_verifierKey(user), await _newVerifier(password));
    await _saveSession(user.trim(), password);
  }

  static Future<String> readToken({
    required String baseUrl,
    required String userName,
  }) async {
    final raw = await _readSecret(_tokenSecureKey, _tokenFallbackKey);
    if (raw.isEmpty) return '';
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return data['baseUrl'] == baseUrl &&
            _sameUser(data['user'] as String, userName)
        ? data['token'] as String
        : '';
  }

  static Future<void> saveToken(
    String token, {
    required String baseUrl,
    required String userName,
  }) async {
    await _writeSecret(
      _tokenSecureKey,
      _tokenFallbackKey,
      jsonEncode({'token': token, 'baseUrl': baseUrl, 'user': userName}),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_verifierKey(userName)}:backend', baseUrl);
  }

  static Future<String> linkedBackend(String userName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${_verifierKey(userName)}:backend') ?? '';
  }

  static Future<bool> hasAnyLocalAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys().any((key) => key.startsWith(_verifierPrefix)) ||
        (prefs.getString(passwordKey)?.isNotEmpty ?? false);
  }

  static Future<void> queueCurrentTokenForRevocation(String userName) async {
    final raw = await _readSecret(_tokenSecureKey, _tokenFallbackKey);
    if (raw.isEmpty) return;
    final session = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (!_sameUser(session['user']?.toString() ?? '', userName) ||
        (session['token']?.toString().isEmpty ?? true) ||
        (session['baseUrl']?.toString().isEmpty ?? true)) {
      return;
    }
    final pending = await pendingRevocations();
    if (!pending.any((item) => item['token'] == session['token'])) {
      pending.add(session.map((key, value) => MapEntry(key, value.toString())));
    }
    await _writeSecret(
      _pendingRevocationsSecureKey,
      _tokenFallbackKey,
      jsonEncode(pending.skip(max(0, pending.length - 10)).toList()),
    );
  }

  static Future<List<Map<String, String>>> pendingRevocations() async {
    final raw = await _readSecret(
      _pendingRevocationsSecureKey,
      _tokenFallbackKey,
    );
    if (raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (item) => Map<String, String>.from(
              (item as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            ),
          )
          .where(
            (item) =>
                item['token']?.isNotEmpty == true &&
                item['baseUrl']?.isNotEmpty == true,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> completeRevocation(String token) async {
    final remaining = (await pendingRevocations())
        .where((item) => item['token'] != token)
        .toList();
    await _writeSecret(
      _pendingRevocationsSecureKey,
      _tokenFallbackKey,
      remaining.isEmpty ? '' : jsonEncode(remaining),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    // Mark signed-out before touching platform storage so a storage failure
    // cannot silently restore a session on the next launch.
    await prefs.remove(userKey);
    await _writeSecret(_passwordSecureKey, _passwordFallbackKey, '');
    await _writeSecret(_tokenSecureKey, _tokenFallbackKey, '');
    await prefs.remove(userKey);
    await prefs.remove(passwordKey);
  }

  static Future<void> _saveSession(String user, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeSecret(_passwordSecureKey, _passwordFallbackKey, password);
    await _writeSecret(_tokenSecureKey, _tokenFallbackKey, '');
    await prefs.setString(userKey, user);
    await prefs.remove(passwordKey);
  }

  static Future<void> _saveVerifierIfMissing(
    SharedPreferences prefs,
    String user,
    String password,
  ) async {
    final key = _verifierKey(user);
    if (!(prefs.getString(key)?.isNotEmpty ?? false)) {
      await prefs.setString(key, await _newVerifier(password));
    }
  }

  static Future<String> _readSecret(String key, String fallbackKey) async {
    await (await SharedPreferences.getInstance()).remove(fallbackKey);
    try {
      return await _secure.read(key: key) ?? '';
    } catch (_) {
      throw StateError(
        'Secure storage is unavailable. On web, open the app using HTTPS or localhost.',
      );
    }
  }

  static Future<void> _writeSecret(
    String key,
    String fallbackKey,
    String value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(fallbackKey);
    try {
      if (value.isEmpty) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {
      throw StateError(
        'Secure storage is unavailable. On web, open the app using HTTPS or localhost.',
      );
    }
  }

  static String? validateCredentials(
    String name,
    String password, {
    bool existing = false,
  }) {
    if (name.isEmpty ||
        name.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      return 'Enter a username with 1–80 characters.';
    }
    if (password.length < (existing ? 1 : 8) || password.length > 256) {
      return 'Use a password with 8–256 characters.';
    }
    return null;
  }

  static String _verifierKey(String user) =>
      '$_verifierPrefix${sha256.convert(utf8.encode(user.trim().toLowerCase()))}';

  static bool _sameUser(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  static Future<String> _newVerifier(String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    return '3:${base64UrlEncode(salt)}:${base64UrlEncode(await _derive(password, salt, 600000))}';
  }

  static Future<bool> _matchesVerifier(String password, String verifier) async {
    final parts = verifier.split(':');
    if (parts.length != 3 || !['2', '3'].contains(parts.first)) return false;
    try {
      final salt = base64Url.decode(parts[1]);
      final expected = base64Url.decode(parts[2]);
      final iterations = parts.first == '3' ? 600000 : 80000;
      final actual = await _derive(password, salt, iterations);
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var index = 0; index < actual.length; index += 1) {
        difference |= actual[index] ^ expected[index];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }

  static bool _needsRehash(String verifier) => !verifier.startsWith('3:');

  static Future<List<int>> _derive(
    String password,
    List<int> salt,
    int iterations,
  ) async {
    final algorithm = cryptography.Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }
}

class TaskStore {
  TaskStore._(this._prefs, this._tasksKey, this._assignmentsKey);

  static const tasksKey = 'task-reminder-tasks-v1';
  static const assignmentsKey = 'task-reminder-assignments-v1';
  static const legacyOwnerKey = 'task-reminder-legacy-owner';

  final SharedPreferences _prefs;
  final String _tasksKey;
  final String _assignmentsKey;

  static String tasksKeyFor(String userName) =>
      '$tasksKey:${_accountKey(userName)}';

  static String assignmentsKeyFor(String userName) =>
      '$assignmentsKey:${_accountKey(userName)}';

  static Future<TaskStore> load({String userName = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    if (userName.trim().isEmpty) {
      return TaskStore._(prefs, tasksKey, assignmentsKey);
    }
    final scopedTasksKey = tasksKeyFor(userName);
    final scopedAssignmentsKey = assignmentsKeyFor(userName);
    final owner =
        prefs.getString(legacyOwnerKey) ??
        prefs.getString(AuthCache.userKey) ??
        '';
    final ownsLegacy =
        owner.trim().toLowerCase() == userName.trim().toLowerCase();
    if (ownsLegacy &&
        !prefs.containsKey(scopedTasksKey) &&
        prefs.containsKey(tasksKey)) {
      await prefs.setString(scopedTasksKey, prefs.getString(tasksKey) ?? '[]');
    }
    if (ownsLegacy &&
        !prefs.containsKey(scopedAssignmentsKey) &&
        prefs.containsKey(assignmentsKey)) {
      await prefs.setString(
        scopedAssignmentsKey,
        prefs.getString(assignmentsKey) ?? '[]',
      );
    }
    return TaskStore._(prefs, scopedTasksKey, scopedAssignmentsKey);
  }

  List<TaskItem> tasks() =>
      allTasks().where((item) => !item.isDeleted).toList()
        ..sort((a, b) => a.title.compareTo(b.title));

  List<TaskItem> allTasks() {
    final raw = _prefs.getString(_tasksKey);
    if (raw == null || raw.isEmpty) return _seedTasks();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded
          .map(
            (item) => TaskItem.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList();
      return _dedupeTasks(items);
    } catch (_) {
      throw const FormatException(
        'Saved tasks could not be read. Original data has been preserved; restore a backup before making changes.',
      );
    }
  }

  List<TaskAssignment> assignments() =>
      allAssignments().where((item) => !item.isDeleted).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  List<TaskAssignment> allAssignments() {
    final raw = _prefs.getString(_assignmentsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) =>
                TaskAssignment.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList();
    } catch (_) {
      throw const FormatException(
        'Saved schedules could not be read. Original data has been preserved; restore a backup before making changes.',
      );
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
      _tasksKey,
      jsonEncode(deduped.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> saveAssignments(List<TaskAssignment> items) async {
    final byId = <String, TaskAssignment>{};
    for (final item in items) {
      final previous = byId[item.id];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        byId[item.id] = item;
      }
    }
    final sorted = byId.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    await _prefs.setString(
      _assignmentsKey,
      jsonEncode(sorted.map((item) => item.toJson()).toList()),
    );
  }

  Future<TaskItem> addTask(TaskItem task) async {
    _validateTask(task);
    final items = allTasks();
    final key = normalizedTaskTitle(task.title);
    final existing = items.where(
      (item) => !item.isDeleted && normalizedTaskTitle(item.title) == key,
    );
    if (existing.isNotEmpty) return existing.first;
    items.add(task);
    await saveTasks(items);
    return task;
  }

  Future<void> addAssignment(TaskAssignment assignment) async {
    final items = allAssignments();
    final exists = items.any(
      (item) =>
          !item.isDeleted &&
          item.taskId == assignment.taskId &&
          isSameDay(item.date, assignment.date),
    );
    if (!exists) {
      items.add(assignment);
      await saveAssignments(items);
    }
  }

  Future<void> updateTask(TaskItem task) async {
    _validateTask(task);
    if (tasks().any(
      (item) =>
          item.id != task.id &&
          normalizedTaskTitle(item.title) == normalizedTaskTitle(task.title),
    )) {
      throw const FormatException(
        'A task with this title already exists. Choose a different title.',
      );
    }
    final items = allTasks()
        .map((item) => item.id == task.id ? task : item)
        .toList();
    await saveTasks(items);
  }

  Future<void> removeTask(String taskId) async {
    final now = DateTime.now();
    final taskItems = allTasks()
        .map(
          (item) => item.id == taskId
              ? item.copyWith(updatedAt: now, deletedAt: now)
              : item,
        )
        .toList();
    final assignmentItems = allAssignments()
        .map(
          (item) => item.taskId == taskId
              ? item.copyWith(updatedAt: now, deletedAt: now)
              : item,
        )
        .toList();
    await Future.wait([saveTasks(taskItems), saveAssignments(assignmentItems)]);
  }

  Future<void> updateAssignment(TaskAssignment assignment) async {
    final items = allAssignments()
        .map((item) => item.id == assignment.id ? assignment : item)
        .toList();
    await saveAssignments(items);
  }

  Future<void> markDone(String assignmentId) async {
    final now = DateTime.now();
    final items = allAssignments()
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
    final items = allAssignments()
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
    final items = allAssignments()
        .map(
          (item) => !item.isDeleted && isSameDay(item.date, date) && !item.done
              ? item.copyWith(completedAt: now, updatedAt: now)
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> moveAssignment(String assignmentId, DateTime date) async {
    final now = DateTime.now();
    final items = allAssignments()
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
    final items = allAssignments()
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
    final now = DateTime.now();
    final items = allAssignments()
        .map(
          (item) => item.id == assignmentId
              ? item.copyWith(updatedAt: now, deletedAt: now)
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> restoreAssignment(TaskAssignment assignment) async {
    final now = DateTime.now();
    final items = allAssignments()
        .map(
          (item) => item.id == assignment.id
              ? assignment.copyWith(updatedAt: now, clearDeletedAt: true)
              : item,
        )
        .toList();
    await saveAssignments(items);
  }

  Future<void> replaceAll(TaskSyncData data) async {
    // Update both preference caches before yielding to other UI mutations.
    await Future.wait([
      saveTasks([...data.tasks]),
      saveAssignments([...data.assignments]),
    ]);
  }

  static void _validateTask(TaskItem task) {
    if (task.title.trim().isEmpty ||
        task.title.length > 200 ||
        task.note.length > 2000) {
      throw const FormatException(
        'Use a title of 1–200 characters and a note of at most 2000 characters.',
      );
    }
  }

  List<TaskItem> _dedupeTasks(List<TaskItem> items) {
    final byId = <String, TaskItem>{};
    for (final item in items) {
      final previous = byId[item.id];
      if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
        byId[item.id] = item;
      }
    }
    // Distinct IDs may already be referenced by schedules on another device.
    return byId.values.toList();
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

  static String _accountKey(String userName) =>
      sha256.convert(utf8.encode(userName.trim().toLowerCase())).toString();
}
