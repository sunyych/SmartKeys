import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'app_library/app_library.dart';

class AppLibraryBundle {
  AppLibraryBundle._(this.app, this.pngBytes, this.iconHash);
  final AppLibraryApp app;
  final Uint8List pngBytes;
  final String iconHash;
  static const maxBytes = 128 * 1024;
  static AppLibraryBundle decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('App bundle exceeds its size limit');
    }
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map ||
        raw.length != 3 ||
        (raw['schemaVersion'] is! int || raw['schemaVersion'] != 1) ||
        raw['app'] is! Map ||
        raw['icon'] is! Map) {
      throw const FormatException('Invalid App bundle');
    }
    final app = AppLibraryApp.fromJson(
      Map<String, dynamic>.from(raw['app'] as Map),
    );
    final registered = AppLibraryCatalog.builtin.appById(app.id);
    if (registered == null ||
        registered.id != app.id ||
        jsonEncode(registered.toJson()) != jsonEncode(app.toJson())) {
      throw const FormatException(
        'This App bundle is not a reviewed catalog publication',
      );
    }
    final icon = raw['icon'] as Map;
    if (icon.length != 3 ||
        icon['id'] != app.iconId ||
        icon['sha256'] is! String ||
        icon['pngBase64'] is! String ||
        (icon['pngBase64'] as String).length > 87384) {
      throw const FormatException('Invalid bundle icon association');
    }
    final png = base64Decode(icon['pngBase64'] as String);
    if (base64Encode(png) != icon['pngBase64']) {
      throw const FormatException('Noncanonical bundle encoding');
    }
    if (png.length < 24 || png.length > 65536 || !_signature(png)) {
      throw const FormatException('Invalid bundle PNG');
    }
    final header = ByteData.sublistView(png);
    final width = header.getUint32(16), height = header.getUint32(20);
    if (width < 1 || height < 1 || width > 512 || height > 512) {
      throw const FormatException('Invalid bundle icon dimensions');
    }
    final hash = sha256.convert(png).toString();
    final expected = registeredAppIconHash(app.iconId);
    if (hash != icon['sha256'] || hash != expected) {
      throw const FormatException(
        'Bundle icon does not match the registered artwork',
      );
    }
    final decoded = image.decodePng(png);
    if (decoded == null || decoded.width != width || decoded.height != height) {
      throw const FormatException('Invalid bundle PNG');
    }
    return AppLibraryBundle._(app, png.asUnmodifiableView(), hash);
  }

  static bool _signature(List<int> bytes) => const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ].asMap().entries.every((e) => bytes[e.key] == e.value);
}
