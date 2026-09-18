import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietnam_map_01/src/repositories/photo_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android save uses the system picker with the original image bytes',
    () async {
      final temp = await Directory.systemTemp.createTemp('vmc-photo-export-');
      final source = File('${temp.path}/lake.png');
      final bytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      await source.writeAsBytes(bytes);
      final channel = const MethodChannel('vietnam_map_checkin/photos');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'saveImage');
            final arguments = Map<String, Object?>.from(call.arguments as Map);
            expect(arguments['name'], 'lake.png');
            expect(arguments['mimeType'], 'image/png');
            expect(arguments['bytes'], bytes);
            return true;
          });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
        await temp.delete(recursive: true);
      });

      final saved = await PhotoExport.save(
        localPhoto: 'local:${source.path}',
        remotePhoto: '',
        baseUrl: '',
        fileName: '../lake.png',
      );
      expect(saved, isTrue);
    },
  );
}
