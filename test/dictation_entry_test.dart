import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/dictation_entry_consent.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'legacy first-use acknowledgement does not skip output guidance',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'dictation.entry_explained.v1': true,
        'dictation.entry_explained.v4': true,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ensureDictationEntryExplained(context),
                child: const Text('Voice input'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Voice input'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictation-entry-explanation')),
        findsOneWidget,
      );
      expect(
        find.textContaining('LumiaKey Desktop sends only finalized text'),
        findsOneWidget,
      );
    },
  );

  testWidgets('compact local dictation stays available in ChatGPT workspace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(915, 412);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => harness.dispose());
    harness.companion.host.value = connectedCompanionHost;
    harness.companion.status.value = CompanionSyncStatus.ready;
    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'chatgpt', 'cursor'},
      running: const {'chatgpt', 'cursor'},
      foreground: 'chatgpt',
    );
    final target = harness.controller.activeComputer;
    expect(target, isNotNull);
    await harness.controller.saveComputerSetup(
      target!,
      ComputerSetup(applicationIds: const ['chatgpt', 'cursor']),
    );
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('local-quick-output')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dictation-entry-explanation')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('local-dictation-panel')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('dictation-explanation-cancel')),
    );
    await tester.pumpAndSettle();
    expect(harness.companion.remoteActions, isEmpty);

    await tester.tap(find.byKey(const ValueKey('workspace-app-chatgpt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remote-layout-chatgpt')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-app-codex')), findsNothing);
    expect(find.byKey(const ValueKey('home-tab-vibe-coding')), findsNothing);
    expect(find.textContaining('is ready'), findsNothing);
    expect(find.byKey(const ValueKey('local-quick-output')), findsOneWidget);
    expect(find.byKey(const ValueKey('vibe-dictation-start')), findsNothing);
    expect(find.byKey(const ValueKey('vibe-dictation-stop')), findsNothing);
    expect(find.byKey(const ValueKey('vibe-app-choices')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('local-quick-output')))
          .onPressed,
      isNotNull,
    );
    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'chatgpt', 'cursor'},
      running: const {'chatgpt', 'cursor'},
      foreground: 'cursor',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('local-quick-output')))
          .onPressed,
      isNotNull,
    );
  });
}
