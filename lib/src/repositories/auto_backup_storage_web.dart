import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class AutoBackupStorage {
  static Future<void> save(Uint8List bytes) async {
    await (await SharedPreferences.getInstance()).setString(
      'vmc-auto-backup-payload',
      base64Encode(bytes),
    );
  }
}
