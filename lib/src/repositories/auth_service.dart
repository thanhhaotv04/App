import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthService {
  const AuthService({required this.baseUrl, this.client});

  final String baseUrl;
  final http.Client? client;

  Future<String> register(String name, String password) async {
    return (await registerSession(name, password)).name;
  }

  Future<AuthSession> registerSession(String name, String password) async {
    final data = await _post('/api/auth/register', {
      'name': name,
      'password': password,
    });
    return AuthSession.fromJson(data, fallbackName: name);
  }

  Future<String> login(String name, String password) async {
    return (await loginSession(name, password)).name;
  }

  Future<AuthSession> loginSession(String name, String password) async {
    final data = await _post('/api/auth/login', {
      'name': name,
      'password': password,
    });
    return AuthSession.fromJson(data, fallbackName: name);
  }

  Future<void> resetPassword(
    String name,
    String currentPassword,
    String newPassword,
  ) async {
    await _post('/api/auth/reset-password', {
      'name': name,
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<String> updateAccount({
    required String name,
    required String currentPassword,
    String? newName,
    String? newPassword,
  }) async {
    return (await updateAccountSession(
      name: name,
      currentPassword: currentPassword,
      newName: newName,
      newPassword: newPassword,
    )).name;
  }

  Future<AuthSession> updateAccountSession({
    required String name,
    required String currentPassword,
    String? newName,
    String? newPassword,
    String? token,
  }) async {
    final data = await _post(
      '/api/auth/update',
      {
        'name': name,
        if (newName != null && newName.trim().isNotEmpty)
          'newName': newName.trim(),
        if (newPassword != null && newPassword.isNotEmpty)
          'newPassword': newPassword,
      },
      headers: {
        if (token?.isNotEmpty == true) 'Authorization': 'Bearer $token',
        'X-Password': currentPassword,
      },
    );
    return AuthSession.fromJson(data, fallbackName: newName ?? name);
  }

  Future<void> logout({String? token}) async {
    await _post(
      '/api/auth/logout',
      const {},
      headers: {
        if (token?.trim().isNotEmpty == true)
          'Authorization': 'Bearer ${token!.trim()}',
      },
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final response =
        await (client?.post(
                  Uri.parse('$baseUrl$path'),
                  headers: {'Content-Type': 'application/json', ...headers},
                  body: jsonEncode(body),
                ) ??
                http.post(
                  Uri.parse('$baseUrl$path'),
                  headers: {'Content-Type': 'application/json', ...headers},
                  body: jsonEncode(body),
                ))
            .timeout(const Duration(seconds: 5));
    Map<String, dynamic> data = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        data['message']?.toString() ??
            data['error']?.toString() ??
            'Authentication failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return data;
  }
}

class AuthSession {
  const AuthSession({required this.name, required this.token});

  final String name;
  final String token;

  factory AuthSession.fromJson(
    Map<String, dynamic> json, {
    required String fallbackName,
  }) => AuthSession(
    name: json['name']?.toString() ?? fallbackName,
    token: json['token']?.toString() ?? '',
  );
}

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
