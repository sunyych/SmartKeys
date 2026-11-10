import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class DesktopShortcutTransferService {
  const DesktopShortcutTransferService();

  static const format = 'lumiakeys.desktop.shortcuts';
  static const version = 1;
  static const maxLayouts = 64;
  static const maxButtonsPerLayout = 24;
  static const maxTotalButtons = 1024;
  static const _vibeApps = {'codex', 'claude', 'cursor'};
  static const _vibeSystemActions = {
    'comma',
    'period',
    'exclamation',
    'quote',
    'screenshot',
  };

  String encode(DesktopManifest manifest) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'layouts': manifest.layouts.map((layout) => layout.toJson()).toList(),
      });

  List<RemoteShortcutLayout> decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['format'] != format ||
        decoded['version'] != version ||
        decoded['layouts'] is! List) {
      throw const FormatException(
        'This is not a LumiaKey Desktop shortcut JSON file.',
      );
    }
    final layouts = (decoded['layouts']! as List)
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid shortcut layout JSON.');
          }
          return RemoteShortcutLayout.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .toList(growable: false);
    final totalButtons = layouts.fold<int>(
      0,
      (total, layout) => total + layout.buttons.length,
    );
    if (layouts.isEmpty ||
        layouts.length > maxLayouts ||
        totalButtons > maxTotalButtons ||
        layouts.any((layout) => layout.buttons.length > maxButtonsPerLayout) ||
        layouts.map((layout) => layout.id).toSet().length != layouts.length) {
      throw const FormatException('Invalid Desktop shortcut layout set.');
    }
    for (final layout in layouts) {
      for (final button in layout.buttons) {
        if (button.targetType != RemoteTargetType.system) continue;
        final appId = layout.id.startsWith('vibe.')
            ? layout.id.substring('vibe.'.length)
            : '';
        final actionId = button.target ?? '';
        if (!_vibeApps.contains(appId) ||
            !_vibeSystemActions.contains(actionId) ||
            button.id != 'vibe.$appId.$actionId') {
          throw const FormatException('Invalid fixed Desktop system action.');
        }
      }
    }
    return layouts;
  }

  Future<String?> importJson() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (selection == null) return null;
    final selected = selection.files.single;
    final bytes =
        selected.bytes ??
        (selected.path == null
            ? null
            : await File(selected.path!).readAsBytes());
    if (bytes == null) {
      throw const FormatException('Could not read the selected JSON file.');
    }
    return utf8.decode(bytes);
  }

  Future<bool> exportJson(DesktopManifest manifest) async {
    final bytes = Uint8List.fromList(utf8.encode(encode(manifest)));
    final target = await FilePicker.platform.saveFile(
      dialogTitle: 'Export LumiaKey Desktop Shortcuts',
      fileName: 'lumiakey-desktop-shortcuts.json',
      bytes: bytes,
    );
    if (target == null) return false;
    final file = File(target);
    if (!await file.exists()) await file.writeAsBytes(bytes);
    return true;
  }
}
