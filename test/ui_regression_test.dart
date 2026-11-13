import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/desktop_connection_panel.dart';
import 'package:smart_keys/ui/home_screen.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'keyboard icon removal keeps General returning to keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });
      harness.companion.host.value = connectedCompanionHost;
      harness.companion.syncedManifest.value = desktopManifest(
        installed: const {'cursor'},
        running: const {'cursor'},
        foreground: 'cursor',
      );
      harness.companion.status.value = CompanionSyncStatus.ready;
      await harness.controller.saveComputerSetup(
        harness.controller.activeComputer!,
        ComputerSetup(applicationIds: const ['cursor']),
      );

      await tester.pumpWidget(
        SmartKeysScope(
          controller: harness.controller,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-tab-keyboard')),
        findsNothing,
        reason: 'opening Cursor must not restore the removed keyboard icon',
      );
      expect(
        find.byKey(const ValueKey('vibe-shortcut-grid')),
        findsOneWidget,
        reason: 'the Cursor workspace is open when the icon absence is checked',
      );
      expect(
        find.byTooltip('Keyboard shortcuts'),
        findsNothing,
        reason: 'the removed icon tooltip must also stay absent',
      );
      final general = find.byKey(const ValueKey('home-tab-general'));
      await tester.ensureVisible(general);
      expect(
        find.descendant(of: general, matching: find.byType(Icon)),
        findsNothing,
        reason: 'General is a text-only entry',
      );
      await tester.tap(general);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('remote-layout-keyboard')),
        findsOneWidget,
        reason: 'the text-only General entry must still return to keyboard',
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'Desktop pairing has one reachable entry and no toolbar duplicate',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });
      harness.companion.host.value = connectedCompanionHost;
      harness.companion.syncedManifest.value = desktopManifest(
        installed: const {'cursor'},
        running: const {'cursor'},
        foreground: 'cursor',
      );
      harness.companion.status.value = CompanionSyncStatus.ready;
      await harness.controller.saveComputerSetup(
        harness.controller.activeComputer!,
        ComputerSetup(applicationIds: const ['cursor']),
      );
      await tester.pumpWidget(
        SmartKeysScope(
          controller: harness.controller,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('control-menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-desktop-connection')),
        findsNothing,
        reason: 'Desktop pairing must not be duplicated in the toolbar menu',
      );
      expect(find.text('LumiaKey Desktop'), findsNothing);
      expect(find.text('Desktop connection'), findsNothing);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
      await tester.pumpAndSettle();
      final pairing = find.text('Pair or manage LumiaKey Desktop');
      expect(pairing, findsOneWidget);
      await tester.ensureVisible(pairing);
      await tester.tap(pairing);
      await tester.pumpAndSettle();
      expect(
        find.byType(DesktopConnectionPanel),
        findsOneWidget,
        reason:
            'the sole pairing entry must open the real Desktop connection panel',
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'Cursor shortcut grid fills landscape safe width',
    (tester) async {
      const viewport = Size(844, 390);
      const safeLeft = 24.0;
      const safeRight = 32.0;
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(
        left: safeLeft,
        right: safeRight,
      );
      tester.view.padding = const FakeViewPadding(
        left: safeLeft,
        right: safeRight,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);

      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });
      harness.companion.host.value = connectedCompanionHost;
      harness.companion.syncedManifest.value = desktopManifest(
        installed: const {'cursor'},
        running: const {'cursor'},
        foreground: 'cursor',
      );
      harness.companion.status.value = CompanionSyncStatus.ready;
      await harness.controller.saveComputerSetup(
        harness.controller.activeComputer!,
        ComputerSetup(applicationIds: const ['cursor']),
      );

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-app-cursor')));
      await tester.pumpAndSettle();

      final grid = tester.getRect(
        find.byKey(const ValueKey('vibe-shortcut-grid')),
      );
      expect(
        grid.left,
        closeTo(safeLeft, 0.5),
        reason: 'grid starts at safe left',
      );
      expect(
        grid.right,
        closeTo(viewport.width - safeRight, 0.5),
        reason: 'grid reaches the asymmetric safe right edge',
      );
      final firstButton = find.byKey(
        const ValueKey('vibe-button-vibe.cursor.project'),
      );
      final fifthButton = find.byKey(
        const ValueKey('vibe-button-vibe.cursor.previousChat'),
      );
      expect(firstButton.hitTestable(), findsOneWidget);
      expect(fifthButton.hitTestable(), findsOneWidget);
      final firstTile = tester.getRect(firstButton);
      expect(
        firstTile.left,
        closeTo(safeLeft + 10, 0.5),
        reason: 'the grid keeps its intended 10dp inset from the safe edge',
      );
      const expectedTileWidth = (844 - 24 - 32 - 20 - 4 * 6) / 5;
      expect(
        firstTile.width,
        closeTo(expectedTileWidth, 0.5),
        reason: 'Cursor tile width uses all five landscape columns',
      );
      final fifthTile = tester.getRect(fifthButton);
      expect(
        fifthTile.right,
        closeTo(viewport.width - safeRight - 10, 0.5),
        reason: 'the fifth Cursor tile reaches the safe right inset',
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
