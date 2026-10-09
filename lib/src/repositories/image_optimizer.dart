import 'dart:typed_data';

import 'package:image/image.dart' as img;

class OptimizedImage {
  const OptimizedImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

class ImageOptimizer {
  const ImageOptimizer();

  Future<OptimizedImage> optimize(List<int> source, String fileName) async {
    final bytes = Uint8List.fromList(source);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('The selected file is not a valid image.');
    }
    final oriented = img.bakeOrientation(decoded);
    for (final frame in oriented.frames) {
      frame.exif = img.ExifData();
      frame.iccProfile = null;
      frame.textData = null;
    }
    const maxSide = 2048;
    final needsResize = oriented.width > maxSide || oriented.height > maxSide;
    final resized = needsResize
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? maxSide : null,
            height: oriented.height > oriented.width ? maxSide : null,
            interpolation: img.Interpolation.average,
          )
        : oriented;
    final base = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final animated = resized.numFrames > 1;
    final transparent = resized.numChannels == 4;
    final encoded = animated
        ? img.encodeGif(resized)
        : transparent
        ? img.encodePng(resized)
        : img.encodeJpg(resized, quality: 86);
    final extension = animated
        ? 'gif'
        : transparent
        ? 'png'
        : 'jpg';
    return OptimizedImage(
      bytes: Uint8List.fromList(encoded),
      fileName: '${base.isEmpty ? 'photo' : base}.$extension',
    );
  }
}
