import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/config.dart';

class ProfileTransferService {
  const ProfileTransferService();

  Future<bool> exportProfile(ProfileConfig profile) async {
    final bytes = Uint8List.fromList(utf8.encode(encodeProfile(profile)));
    final target = await FilePicker.platform.saveFile(
      dialogTitle: 'Export SmartKeys Profile',
      fileName: '${_safeName(profile.name)}.smartkeys.json',
      bytes: bytes,
    );
    if (target == null) return false;
    final file = File(target);
    if (!await file.exists()) await file.writeAsBytes(bytes);
    return true;
  }

  Future<ProfileConfig?> importProfile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (selection == null) return null;
    final selected = selection.files.single;
    final bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
    return decodeImportedProfile(utf8.decode(bytes));
  }

  Future<ProfileConfig> importProfileFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim();
    if (raw == null || raw.isEmpty) {
      throw const FormatException(
        'The clipboard does not contain profile JSON.',
      );
    }
    return decodeImportedProfile(raw);
  }

  Future<void> copyProfileJson(ProfileConfig profile) =>
      Clipboard.setData(ClipboardData(text: encodeProfile(profile)));

  String encodeProfile(ProfileConfig profile) =>
      const JsonEncoder.withIndent('  ').convert(profile.toJson());

  ProfileConfig decodeImportedProfile(String raw) {
    final trimmed = raw.trim();
    final fenced = RegExp(
      r'^```(?:json)?\s*(.*?)\s*```$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);
    final decoded = jsonDecode(fenced?.group(1) ?? trimmed);
    if (decoded is! Map<String, dynamic> ||
        decoded['name'] is! String ||
        (decoded['buttons'] is! List && decoded['wheel'] is! Map)) {
      throw const FormatException(
        'This is not a valid SmartKeys profile JSON.',
      );
    }
    final profile = ProfileConfig.fromJson(decoded);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return profile.copyWith(
      id: 'profile_imported_$stamp',
      name: '${profile.name} (Imported)',
      isBuiltInTemplate: false,
      createdAt: stamp ~/ 1000,
      updatedAt: stamp ~/ 1000,
    );
  }

  String _safeName(String input) => input
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}
