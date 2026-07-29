import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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

class MoneySyncService {
  const MoneySyncService({
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

  Future<MoneySyncData> syncTwoWay(
    List<Tx> localTransactions,
    List<RecurringExpense> localRecurring,
  ) async {
    await _ensureBackendAccount();
    final remote = await pullRemote();
    final transactions = _mergeTransactions(
      localTransactions,
      remote.transactions,
    );
    final recurring = _mergeRecurring(localRecurring, remote.recurring);
    await _saveRemote(transactions, recurring);
    return MoneySyncData(transactions, recurring);
  }

  Future<MoneySyncData> pullRemote() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/money-manager/data'),
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
    final txJson = data['transactions'] as List? ?? const [];
    final recurringJson = data['recurring'] as List? ?? const [];
    return MoneySyncData(
      txJson
          .map((item) => Tx.fromJson(Map<String, Object?>.from(item as Map)))
          .toList(),
      recurringJson
          .map(
            (item) => RecurringExpense.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  Future<void> _saveRemote(
    List<Tx> transactions,
    List<RecurringExpense> recurring,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/money-manager/data'),
      headers: {'Content-Type': 'application/json', ..._authHeaders},
      body: jsonEncode({
        'transactions': transactions.map((item) => item.toJson()).toList(),
        'recurring': recurring.map((item) => item.toJson()).toList(),
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

  List<Tx> _mergeTransactions(List<Tx> local, List<Tx> remote) {
    final byId = <String, Tx>{for (final item in local) item.id: item};
    for (final item in remote) {
      final previous = byId[item.id];
      if (previous == null || item.date.isAfter(previous.date)) {
        byId[item.id] = item;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }

  List<RecurringExpense> _mergeRecurring(
    List<RecurringExpense> local,
    List<RecurringExpense> remote,
  ) {
    final byId = <String, RecurringExpense>{
      for (final item in local) item.id: item,
    };
    for (final item in remote) {
      final previous = byId[item.id];
      if (previous == null ||
          item.lastAppliedAt.isAfter(previous.lastAppliedAt)) {
        byId[item.id] = item;
      }
    }
    return byId.values.toList();
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
      if (error.message == 'Incorrect password. Please try again.' ||
          error.message.toLowerCase().contains('incorrect password')) {
        throw const AuthException(
          'Backend password is different. Sign out, then sign in with the '
          'backend password or reset it.',
        );
      }
      rethrow;
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

  static const currentVersionName = '1.0.8';
  static const currentVersionCode = 9;
  static const _channel = MethodChannel('money_manager/update');

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
      '${dir.path}${Platform.pathSeparator}money-manager-${info.versionCode}.apk',
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
        ? Directory('/data/user/0/com.thanhhao.money_manager/cache')
        : Directory.systemTemp;
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    return dir;
  }
}
