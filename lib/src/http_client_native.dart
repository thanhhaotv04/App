import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

SecurityContext? _context;

void configureTrustedCa(List<int> certificate) {
  _context = SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(certificate);
}

http.Client createClient() => IOClient(HttpClient(context: _context));
