import 'package:flutter/foundation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import 'companion_service.dart';

/// Lite never opens a socket, discovers computers, or executes Desktop actions.
class DisabledCompanionService implements CompanionService {
  final _host = ValueNotifier<CompanionHost?>(null);
  final _manifest = ValueNotifier<DesktopManifest?>(null);
  final _status = ValueNotifier(CompanionSyncStatus.disconnected);
  final _error = ValueNotifier<String?>(null);

  @override
  ValueListenable<CompanionHost?> get activeHost => _host;
  @override
  ValueListenable<DesktopManifest?> get manifest => _manifest;
  @override
  ValueListenable<CompanionSyncStatus> get syncStatus => _status;
  @override
  ValueListenable<String?> get errorMessage => _error;

  @override
  Future<void> start() async {}
  @override
  Future<void> refreshManifest() async {}

  Never _unavailable() => throw UnsupportedError(
    'LumiaKey Lite uses Bluetooth HID. Desktop actions require LumiaKey.',
  );

  @override
  Future<void> execute(String command) async => _unavailable();
  @override
  Future<void> executeRemote(RemoteActionRequest request) async =>
      _unavailable();
  @override
  Future<void> sendDictation({
    required String sessionId,
    required int sequence,
    required String text,
  }) async => _unavailable();

  @override
  void dispose() {
    _host.dispose();
    _manifest.dispose();
    _status.dispose();
    _error.dispose();
  }
}
