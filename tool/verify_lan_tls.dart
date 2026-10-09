// dart run tool/verify_lan_tls.dart <HTTPS origin> <public CA PEM>
import 'dart:convert';
import 'dart:io';
import 'package:money_manager/src/http_client_native.dart' as network;

Future<void> main(List<String> args) async {
  final uri = Uri.parse('${args[0]}/api/health');
  final untrusted = network.createClient();
  var rejected = false;
  try {
    await untrusted.get(uri);
  } catch (_) {
    rejected = true;
  } finally {
    untrusted.close();
  }
  if (!rejected) {
    throw StateError('Expected the private LAN CA to require explicit trust.');
  }
  network.configureTrustedCa(await File(args[1]).readAsBytes());
  final trusted = network.createClient();
  try {
    final response = await trusted.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['protocol'] != 3) {
      throw StateError('HTTPS backend verification failed.');
    }
    stdout.writeln(
      'PASS: untrusted LAN certificate rejected; bundled CA accepted by the app HTTP client; backend protocol 3.',
    );
  } finally {
    trusted.close();
  }
}
