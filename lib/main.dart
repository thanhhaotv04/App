import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'src/app.dart';
import 'src/http_client_native.dart'
    if (dart.library.js_interop) 'src/http_client_web.dart'
    as network;

Future<void> main() => http.runWithClient(() async {
  WidgetsFlutterBinding.ensureInitialized();
  final certificate = await rootBundle.load('assets/certificates/lan-ca.pem');
  network.configureTrustedCa(
    certificate.buffer.asUint8List(
      certificate.offsetInBytes,
      certificate.lengthInBytes,
    ),
  );
  runApp(const MoneyManagerApp());
}, network.createClient);
