import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/home_screen.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'selecting a standalone app opens controls without launching it',
    (tester) async {
      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      final target = harness.controller.activeComputer!;
      await harness.controller.saveComputerSetup(
        target,
        ComputerSetup(
          applicationIds: const ['chrome'],
          bindings: const {
            'chrome': {'launch': 'Ctrl+Alt+1', 'newTab': 'Ctrl+Alt+2'},
          },
        ),
      );

      await tester.pumpWidget(
        SmartKeysScope(
          controller: harness.controller,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('workspace-app-chrome')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('standalone-app-title')),
        findsOneWidget,
      );
      expect(harness.hid.steppedActions, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('standalone-action-chrome-newTab')),
      );
      await tester.pumpAndSettle();
      expect(harness.hid.steppedActions, hasLength(1));
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'desktop app shortcuts stay disabled until selected app activation returns',
    (tester) async {
      final companion = _DelayedLaunchCompanion();
      final harness = await TestHarness.create(
        seedComputerSetup: false,
        companionService: companion,
      );
      addTearDown(harness.dispose);
      final starter = DesktopManifest.starter();
      companion.host.value = connectedCompanionHost;
      companion.syncedManifest.value = starter.copyWith(
        computerId: 'desktop-app-focus-test',
        applications: [
          for (final app in starter.applications)
            if (app.id == 'vscode') app.copyWith(detected: true),
        ],
      );
      companion.status.value = CompanionSyncStatus.ready;
      final target = harness.controller.activeComputer!;
      await harness.controller.saveComputerSetup(
        target,
        ComputerSetup(
          applicationIds: const ['vscode'],
          operatingSystem: ComputerOperatingSystem.windows,
        ),
      );

      await tester.pumpWidget(
        SmartKeysScope(
          controller: harness.controller,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('workspace-app-vscode')));
      await tester.pumpAndSettle();
      expect(companion.launchStarted.isCompleted, isTrue);

      await tester.tap(find.byKey(const ValueKey('remote-button-vscode.open')));
      await tester.pump();
      expect(companion.remoteActions, isEmpty);

      companion.launchGate.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-button-vscode.open')));
      await tester.pumpAndSettle();
      expect(companion.remoteActions.last.kind, RemoteActionKind.button);
      expect(companion.remoteActions.last.buttonId, 'vscode.open');
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}

class _DelayedLaunchCompanion extends RecordingCompanionService {
  final Completer<void> launchStarted = Completer<void>();
  final Completer<void> launchGate = Completer<void>();

  @override
  Future<void> executeRemote(RemoteActionRequest request) async {
    if (request.kind == RemoteActionKind.launchApplication) {
      if (!launchStarted.isCompleted) launchStarted.complete();
      await launchGate.future;
      remoteActions.add(request);
      return;
    }
    await super.executeRemote(request);
  }
}
