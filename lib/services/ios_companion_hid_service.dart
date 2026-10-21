import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/config.dart';
import 'companion_service.dart';
import 'hid_service.dart';

/// iPad keyboard transport. Each chord is delivered as one Desktop shortcut;
/// this adapter does not emulate Bluetooth HID or hold keys between requests.
class IosCompanionHidService implements HidService {
  IosCompanionHidService(this.companion);

  final CompanionService companion;
  final ValueNotifier<HidConnectionStatus> _status = ValueNotifier(
    HidConnectionStatus.unavailable,
  );
  final ValueNotifier<List<HidHost>> _hosts = ValueNotifier(const []);
  final ValueNotifier<HidHost?> _activeHost = ValueNotifier(null);
  final ValueNotifier<String?> _error = ValueNotifier(null);

  @override
  ValueListenable<HidConnectionStatus> get connectionStatus => _status;
  @override
  ValueListenable<List<HidHost>> get pairedHosts => _hosts;
  @override
  ValueListenable<HidHost?> get activeHost => _activeHost;
  @override
  ValueListenable<String?> get errorMessage => _error;

  void _showUnsupported([String? message]) {
    final explanation =
        message ?? 'This input needs Bluetooth HID and is unavailable on iPad.';
    _error.value = explanation;
  }

  Never _rejectUnsupported([String? message]) {
    _showUnsupported(message);
    throw UnsupportedError(_error.value!);
  }

  @override
  Future<void> requestBluetoothAccess() async => _rejectUnsupported();
  @override
  Future<void> makeDiscoverable() async => _rejectUnsupported();
  @override
  Future<void> openBluetoothSettings() async => _rejectUnsupported();
  @override
  Future<void> refreshPairedHosts() async => _rejectUnsupported();
  @override
  Future<void> connectHost(String hostId) async => _rejectUnsupported();
  @override
  Future<void> disconnectHost() async => _rejectUnsupported();
  @override
  Future<void> releaseAllKeys() async {}
  @override
  Future<void> sendRelease(HidAction action) async {}

  @override
  Future<void> sendPress(HidAction action) => _sendChord(action);
  @override
  Future<void> sendStep(HidAction action) => _sendChord(action);

  Future<void> _sendChord(HidAction action) async {
    if (action.type != ActionType.keyboard) {
      _showUnsupported(
        'iPad Desktop mode supports keyboard shortcuts only. Mouse and held-key actions need Bluetooth HID.',
      );
      return;
    }
    final selectedHost = companion.activeHost.value;
    if (selectedHost == null ||
        companion.syncStatus.value != CompanionSyncStatus.ready) {
      _showUnsupported(
        'Connect to LumiaKey Desktop before using keyboard shortcuts.',
      );
      return;
    }
    final rawKey = action.keyCode?.toUpperCase() ?? '';
    final key = rawKey.startsWith('KEY_') ? rawKey.substring(4) : rawKey;
    const modifiers = {
      'CTRL': 'CTRL',
      'CONTROL': 'CTRL',
      'ALT': 'ALT',
      'OPTION': 'ALT',
      'SHIFT': 'SHIFT',
      'META': 'META',
      'COMMAND': 'META',
      'WIN': 'META',
    };
    final keys = <String>[
      ...action.modifiers.map((value) {
        final name = value.toUpperCase().replaceFirst(
          RegExp(r'^(LEFT|RIGHT)_'),
          '',
        );
        return modifiers[name] ?? '';
      }),
      key,
    ];
    if (key.isEmpty || keys.any((value) => value.isEmpty)) {
      _showUnsupported(
        'This keyboard action has an unsupported key or modifier.',
      );
      return;
    }
    try {
      await companion.execute(jsonEncode({'kind': 'shortcut', 'keys': keys}));
      if (companion.syncStatus.value == CompanionSyncStatus.error) {
        _error.value =
            companion.errorMessage.value ?? 'Desktop shortcut failed.';
        return;
      }
      if (companion.activeHost.value != selectedHost ||
          companion.syncStatus.value != CompanionSyncStatus.ready) {
        _error.value =
            'Desktop connection changed before the shortcut was delivered.';
        return;
      }
      _error.value = null;
    } catch (error) {
      _error.value = 'Desktop shortcut failed: $error';
    }
  }

  @override
  Future<void> sendTextBatch({
    required String sessionToken,
    required String expectedAddress,
    required HidTextProfile profile,
    required List<HidTextStroke> strokes,
    required List<int> codePoints,
  }) async =>
      _rejectUnsupported('Text batches are unavailable in iPad Desktop mode.');

  @override
  Future<void> cancelTextBatch(String sessionToken) async => _rejectUnsupported(
    'Text batch cancellation is unavailable in iPad Desktop mode.',
  );

  @override
  void dispose() {
    _status.dispose();
    _hosts.dispose();
    _activeHost.dispose();
    _error.dispose();
  }
}
