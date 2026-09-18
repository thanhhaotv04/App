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
    const maxSide = 2048;
    final needsResize = decoded.width > maxSide || decoded.height > maxSide;
    final needsCompression = bytes.length > 2 * 1024 * 1024;
    if (!needsResize && !needsCompression) {
      return OptimizedImage(bytes: bytes, fileName: fileName);
    }
    final resized = needsResize
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    final base = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return OptimizedImage(
      bytes: Uint8List.fromList(img.encodeJpg(resized, quality: 86)),
      fileName: '${base.isEmpty ? 'photo' : base}.jpg',
    );
  }
}
