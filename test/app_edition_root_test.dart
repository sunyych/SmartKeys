import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/app_edition.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/home_screen.dart';
import 'package:smart_keys/ui/regular_home_screen.dart';

import 'test_support.dart';

void main() {
  testWidgets('default root requires Desktop despite connected Bluetooth HID', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 420);
    final harness = await TestHarness.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      await harness.dispose();
    });

    expect(buildEdition, AppEdition.regular);
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();
    expect(find.byType(RegularHomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(
      find.byKey(const ValueKey('regular-connect-desktop')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('control-button-0')), findsNothing);
    expect(find.byKey(const ValueKey('regular-twelve-key-grid')), findsNothing);
    expect(harness.hid.pressedActions, isEmpty);
    expect(harness.hid.steppedActions, isEmpty);

    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'chatgpt', 'chrome'},
    );
    harness.companion.host.value = connectedCompanionHost;
    harness.companion.status.value = CompanionSyncStatus.ready;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-twelve-key-grid')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('regular-launch-chrome')), findsNothing);
    expect(
      find.byKey(const ValueKey('regular-configure-launchpad')),
      findsOneWidget,
    );
    harness.companion.syncedManifest.value = harness
        .companion
        .syncedManifest
        .value!
        .copyWith(
          launcherApplicationIds: [
            'chrome',
            'chatgpt',
            ...List<String?>.filled(launcherSlotCount - 2, null),
          ],
        );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('regular-launch-chrome')), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
