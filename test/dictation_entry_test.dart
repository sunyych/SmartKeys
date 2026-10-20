import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/dictation_entry_consent.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('homepage quick output and app voice input both gate first use', (
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
      installed: const {'codex'},
      running: const {'codex'},
      foreground: 'codex',
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

    await tester.drag(
      find.byKey(const ValueKey('profile-quick-switch-bar')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    final codexTab = find.byKey(const ValueKey('home-tab-codex'));
    if (codexTab.evaluate().isEmpty) {
      await tester.drag(
        find.byKey(const ValueKey('profile-quick-switch-bar')),
        const Offset(-700, 0),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('home-tab-codex')));
    await tester.pumpAndSettle();
    final voiceButton = find.byKey(const ValueKey('remote-button-codex.voice'));
    expect(voiceButton, findsOneWidget);
    final semanticsNodes = tester.widgetList<Semantics>(
      find.ancestor(of: voiceButton, matching: find.byType(Semantics)),
    );
    expect(
      semanticsNodes.any(
        (node) =>
            node.properties.label ==
            'Application voice input, starts the selected app voice shortcut',
      ),
      isTrue,
    );
    expect(
      find.descendant(of: voiceButton, matching: find.byIcon(Icons.graphic_eq)),
      findsOneWidget,
    );

    await tester.tap(voiceButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dictation-entry-explanation')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('dictation-explanation-accept')),
    );
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool(
        dictationConsentPreferenceKey,
      ),
      isTrue,
    );
    expect(harness.companion.remoteActions.single.buttonId, 'codex.voice');
  });
}
