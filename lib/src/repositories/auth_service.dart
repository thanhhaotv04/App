import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthService {
  const AuthService({required this.baseUrl});

  final String baseUrl;

  Future<String> register(String name, String password) async {
    final data = await _post('/api/auth/register', {
      'name': name,
      'password': password,
    });
    return data['name']?.toString() ?? name;
  }

  Future<String> login(String name, String password) async {
    final data = await _post('/api/auth/login', {
      'name': name,
      'password': password,
    });
    return data['name']?.toString() ?? name;
  }

  Future<void> resetPassword(String name, String newPassword) async {
    await _post('/api/auth/reset-password', {
      'name': name,
      'newPassword': newPassword,
    });
  }

  Future<String> updateAccount({
    required String name,
    required String currentPassword,
    String? newName,
    String? newPassword,
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
      headers: {'X-Password': currentPassword},
    );
    return data['name']?.toString() ?? newName ?? name;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json', ...headers},
      body: jsonEncode(body),
    );
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

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
