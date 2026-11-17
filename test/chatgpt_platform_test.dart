import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'test_support.dart';

void main() {
  testWidgets('ChatGPT follows the connected computer platform', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create(seedComputerSetup: false);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    });

    for (final (platform, authoritative) in [
      ('windows', false),
      ('macos', false),
      ('windows', true),
    ]) {
      final host = CompanionHost(
        name: 'Test $platform',
        platform: platform,
        address: '192.168.1.10',
        port: authoritative ? 45680 : (platform == 'windows' ? 45678 : 45679),
        token: 'test-$platform-$authoritative',
        protocolVersion: 2,
        capabilities: {
          ...connectedCompanionHost.capabilities,
          if (authoritative) 'chatgpt-platform-layout-v1',
        },
      );
      harness.companion.status.value = CompanionSyncStatus.syncing;
      harness.companion.host.value = host;
      // Old hosts send portable bindings. New hosts can send exact custom
      // chords that would otherwise be mistaken for an old platform default.
      final manifest = desktopManifest(
        installed: const {'chatgpt'},
        running: const {'chatgpt'},
        foreground: 'chatgpt',
      ).copyWith(computerId: 'test-$platform-$authoritative');
      harness.companion.syncedManifest.value = authoritative
          ? manifest.copyWith(
              layouts: [
                for (final layout in manifest.layouts)
                  if (layout.id == 'chatgpt')
                    layout.copyWith(
                      buttons: [
                        for (final button in layout.buttons)
                          if (button.id == 'chatgpt.codexMode')
                            button.copyWith(shortcut: const ['CTRL', '3'])
                          else if (button.id == 'chatgpt.newChat')
                            button.copyWith(shortcut: const ['CTRL', 'N']),
                      ],
                    )
                  else
                    layout,
              ],
            )
          : manifest;
      harness.companion.status.value = CompanionSyncStatus.ready;
      await harness.controller.saveComputerSetup(
        harness.controller.activeComputer!,
        ComputerSetup(applicationIds: const ['chatgpt']),
      );
      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-app-chatgpt')));
      await tester.pumpAndSettle();

      final apple = platform == 'macos';
      final mode = find.byKey(
        const ValueKey('remote-button-chatgpt.codexMode'),
      );
      final newChat = find.byKey(
        const ValueKey('remote-button-chatgpt.newChat'),
      );
      expect(
        find.descendant(
          of: mode,
          matching: find.text(apple || authoritative ? 'Ctrl + 3' : 'Alt + 3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: newChat,
          matching: find.text(apple ? 'Command + N' : 'Ctrl + N'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remote-button-chatgpt.codex.searchChats')),
        findsNothing,
      );
      await tester.tap(newChat);
      await tester.pump();
      expect(harness.companion.remoteActions.last.buttonId, 'chatgpt.newChat');
      if (!authoritative) {
        await tester.tap(find.byTooltip('Next bank'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('remote-button-chatgpt.startVoice')),
          apple ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('remote-button-chatgpt.codex.searchChats')),
          findsNothing,
        );
      }
    }
  });
}
