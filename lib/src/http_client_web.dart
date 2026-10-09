import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

void configureTrustedCa(List<int> certificate) {}
http.Client createClient() => BrowserClient();
