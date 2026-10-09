import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backend_config.dart';

class PrivatePhoto {
  static Future<Uint8List?> read({
    required String baseUrl,
    required String photo,
    required Map<String, String> headers,
    http.Client? client,
  }) async {
    final uri = BackendConfig.photoUri(baseUrl, photo);
    final connection = client ?? http.Client();
    try {
      // Never forward credentials to a redirect target, even on this origin.
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      final response = await connection
          .send(request)
          .timeout(const Duration(seconds: 20));
      final body = await http.Response.fromStream(
        response,
      ).timeout(const Duration(seconds: 20));
      return body.statusCode == 200 ? body.bodyBytes : null;
    } finally {
      if (client == null) connection.close();
    }
  }
}
