import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/home_screen.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'compact toolbar scrolls to keyboard profiles and keeps them tappable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      final profile = await harness.controller.createProfile(name: 'Compact');
      final target = harness.controller.activeComputer!;
      final supportedApps = harness
          .controller
          .computerApplicationsOnActiveComputer
          .take(8)
          .map((application) => application.id)
          .toList(growable: false);
      await harness.controller.saveComputerSetup(
        target,
        ComputerSetup(applicationIds: supportedApps),
      );

      await tester.pumpWidget(
        SmartKeysScope(
          controller: harness.controller,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final toolbar = find.byKey(const ValueKey('computer-app-row'));
      expect(toolbar, findsOneWidget);
      final toolbarRect = tester.getRect(toolbar);
      expect(toolbarRect.height, 46);
      expect(find.byKey(const ValueKey('control-menu')), findsOneWidget);
      final profileChip = find.byKey(ValueKey('profile-quick-${profile.id}'));
      await tester.scrollUntilVisible(
        profileChip,
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('profile-quick-switch-bar')),
          matching: find.byType(Scrollable),
        ),
      );
      await Scrollable.ensureVisible(
        tester.element(profileChip),
        alignment: 0.5,
      );
      _expectControlsInRow(tester, toolbarRect, [
        profileChip,
        find.byKey(const ValueKey('control-menu')),
        find.byKey(const ValueKey('local-quick-output')),
      ]);
      await tester.tap(profileChip);
      await tester.pumpAndSettle();
      expect(harness.controller.activeProfile.id, profile.id);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'app workspace toolbar stays single-line and tappable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      harness.companion.syncedManifest.value = desktopManifest(
        installed: const {'cursor'},
        running: const {'cursor'},
        foreground: 'cursor',
      );
      harness.companion.host.value = connectedCompanionHost;
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
      final row = find.byKey(const ValueKey('computer-app-row'));
      final rowRect = tester.getRect(row);
      expect(rowRect.height, 46);
      expect(find.byKey(const ValueKey('control-menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('local-quick-output')), findsOneWidget);

      final lastApp = find.byKey(const ValueKey('workspace-app-cursor'));
      final general = find.byKey(const ValueKey('home-tab-general'));
      expect(find.byKey(const ValueKey('home-tab-keyboard')), findsNothing);
      await Scrollable.ensureVisible(tester.element(lastApp), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(lastApp);
      await tester.pumpAndSettle();
      _expectControlsInRow(tester, rowRect, [
        lastApp,
        find.byKey(const ValueKey('vibe-touchpad-toggle')),
        find.byKey(const ValueKey('local-quick-output')),
        find.byKey(const ValueKey('control-menu')),
      ]);
      await tester.tap(find.byKey(const ValueKey('control-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-desktop-connection')),
        findsNothing,
      );
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        general,
        -80,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('computer-app-scroll-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(general);
      await tester.pumpAndSettle();
      await tester.tap(general);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('remote-layout-keyboard')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
      await tester.pumpAndSettle();
      final pair = find.text('Pair or manage LumiaKey Desktop');
      await tester.ensureVisible(pair);
      await tester.tap(pair);
      await tester.pumpAndSettle();
      expect(
        find.text('Connected to Studio Mac (192.168.1.10)'),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}

void _expectControlsInRow(
  WidgetTester tester,
  Rect row,
  List<Finder> controls,
) {
  for (final control in controls) {
    expect(control.hitTestable(), findsOneWidget);
    final rect = tester.getRect(control);
    expect(rect.top, greaterThanOrEqualTo(row.top));
    expect(rect.bottom, lessThanOrEqualTo(row.bottom));
  }
}
