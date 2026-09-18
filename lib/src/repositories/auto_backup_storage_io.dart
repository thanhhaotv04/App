import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class AutoBackupStorage {
  static Future<void> save(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${directory.path}${Platform.pathSeparator}backups',
    );
    await folder.create(recursive: true);
    await File(
      '${folder.path}${Platform.pathSeparator}automatic.vmcbackup',
    ).writeAsBytes(bytes, flush: true);
  }
}
