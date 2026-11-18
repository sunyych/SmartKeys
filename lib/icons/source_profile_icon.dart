import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'app_icon_validation.dart';
import '../app_library/app_library.dart';

final _verifiedSourceIcons = <String, Uint8List>{};

Uint8List? sourceProfileIcon(RemoteProfile profile) {
  try {
    final encoded = profile.sourceIconPngBase64,
        hash = profile.sourceIconSha256;
    if (encoded == null ||
        encoded.length > 87384 ||
        hash == null ||
        hash != registeredAppIconHash(profile.sourceIconId ?? '')) {
      return null;
    }
    final bytes = base64Decode(encoded);
    if (sha256.convert(bytes).toString() != hash) return null;
    if (_verifiedSourceIcons[hash] case final cached?) return cached;
    if (!AppIconValidation.isValidPng(bytes)) return null;
    if (_verifiedSourceIcons.length >= 32) {
      _verifiedSourceIcons.remove(_verifiedSourceIcons.keys.first);
    }
    return _verifiedSourceIcons[hash] = bytes.asUnmodifiableView();
  } catch (_) {
    return null;
  }
}
