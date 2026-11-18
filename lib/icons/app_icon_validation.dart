import 'dart:typed_data';

import 'package:image/image.dart' as images;

abstract final class AppIconValidation {
  static const maxBytes = 64 * 1024;
  static const maxDimension = 512;

  static bool isValidPng(Uint8List bytes) {
    if (bytes.length < 33 || bytes.length > maxBytes) return false;
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(8) != 13 || header.getUint32(12) != 0x49484452) {
      return false;
    }
    final width = header.getUint32(16);
    final height = header.getUint32(20);
    if (width < 1 ||
        height < 1 ||
        width > maxDimension ||
        height > maxDimension) {
      return false;
    }
    try {
      final decoded = images.decodePng(bytes);
      return decoded != null &&
          decoded.width == width &&
          decoded.height == height;
    } catch (_) {
      return false;
    }
  }
}
