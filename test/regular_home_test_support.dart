import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/regular_home_screen.dart';

import 'test_support.dart';

const regularTestHost = CompanionHost(
  name: 'Studio PC',
  computerId: 'regular-test-pc',
  platform: 'windows',
  address: '192.168.1.20',
  port: 45833,
  token: 'regular-test',
  protocolVersion: 2,
  capabilities: {'manifest', 'apps', 'mouse-control-v1', 'local-dictation-v1'},
);

class ActivatingRegularCompanion extends RecordingCompanionService {
  @override
  Future<void> executeRemote(RemoteActionRequest request) async {
    await super.executeRemote(request);
    final manifest = syncedManifest.value;
    if (request.kind == RemoteActionKind.launchApplication &&
        manifest != null) {
      syncedManifest.value = manifest.copyWith(
        applicationActivationSequence:
            manifest.applicationActivationSequence + 1,
        activatedApplicationId: request.applicationId,
        applications: [
          for (final app in manifest.applications)
            app.copyWith(foreground: app.id == request.applicationId),
        ],
      );
    }
  }
}

void connectRegularHarness(
  TestHarness harness, {
  DesktopManifest? manifest,
  Set<String>? installed,
  List<String?>? launcherSlots,
}) {
  final starter = manifest ?? DesktopManifest.starter();
  harness.companion.syncedManifest.value = starter.copyWith(
    launcherApplicationIds:
        launcherSlots ??
        [
          for (final id
              in [
                    'chatgpt',
                    'chrome',
                    ...starter.applications
                        .map((app) => app.id)
                        .where((id) => id != 'chatgpt' && id != 'chrome'),
                  ]
                  .where((id) => installed?.contains(id) ?? true)
                  .take(launcherSlotCount))
            id,
          for (
            var index = starter.applications
                .where((app) => installed?.contains(app.id) ?? true)
                .length;
            index < launcherSlotCount;
            index++
          )
            null,
        ],
    applications: starter.applications
        .map(
          (app) => app.copyWith(detected: installed?.contains(app.id) ?? true),
        )
        .toList(),
  );
  harness.companion.host.value = regularTestHost;
  harness.companion.status.value = CompanionSyncStatus.ready;
}

Widget regularTestApp(TestHarness harness, {Widget? child}) => SmartKeysScope(
  controller: harness.controller,
  child: MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF67E8F9),
        brightness: Brightness.dark,
        surface: const Color(0xFF10151D),
      ),
      scaffoldBackgroundColor: const Color(0xFF090D12),
    ),
    home: child ?? const RegularHomeScreen(),
  ),
);
