import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/local_dictation_panel.dart';

import 'regular_home_test_support.dart';
import 'test_support.dart';

Future<TestHarness> mountRegular(
  WidgetTester tester, {
  RecordingCompanionService? companion,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(844, 390);
  final harness = await TestHarness.create(companionService: companion);
  connectRegularHarness(harness);
  await tester.pumpWidget(regularTestApp(harness));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    await harness.dispose();
  });
  return harness;
}

class DeferredRegularCompanion extends RecordingCompanionService {
  final launch = Completer<void>();
  @override
  Future<void> executeRemote(RemoteActionRequest request) async {
    remoteActions.add(request);
    if (request.kind == RemoteActionKind.launchApplication) await launch.future;
  }
}

void main() {
  testWidgets('launchpad renders twelve cells and launches Desktop IDs', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    expect(find.byKey(const ValueKey('regular-cell-11')), findsOneWidget);
    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('regular-twelve-key-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
    await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
    await tester.pumpAndSettle();
    expect(
      harness.companion.remoteActions.single.kind,
      RemoteActionKind.launchApplication,
    );
    expect(harness.companion.remoteActions.single.applicationId, 'chrome');
    expect(
      find.byKey(const ValueKey('regular-button-chrome.newTab')),
      findsOneWidget,
    );
    expect(harness.hid.pressedActions, isEmpty);
    expect(harness.hid.steppedActions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'General is keyboard even when Desktop current profile is an app',
    (tester) async {
      final harness = await mountRegular(tester);
      final manifest = harness.companion.syncedManifest.value!;
      harness.companion.syncedManifest.value = manifest.copyWith(
        currentProfileId: 'browser',
        profiles: [
          ...manifest.profiles,
          const RemoteProfile(
            id: 'browser',
            name: 'Chrome',
            layoutId: 'app.chrome',
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('regular-nav-general')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('regular-button-keyboard.copy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('regular-button-keyboard.copy')),
      );
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions.single.buttonId, 'keyboard.copy');
    },
  );

  testWidgets('custom layouts retain buttons beyond twelve through paging', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
    await tester.pumpAndSettle();
    final manifest = harness.companion.syncedManifest.value!;
    final old = manifest.layoutById('app.chrome')!;
    final custom = old.copyWith(
      buttons: List.generate(
        15,
        (index) => RemoteShortcutButton(
          id: 'custom.chrome.$index',
          name: 'Custom $index',
          icon: 'keyboard',
          targetType: RemoteTargetType.keyboardShortcut,
          shortcut: const ['PRIMARY', 'T'],
        ),
      ),
    );
    harness.companion.syncedManifest.value = manifest.copyWith(
      layouts: [
        for (final layout in manifest.layouts)
          layout.id == custom.id ? custom : layout,
      ],
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-button-custom.chrome.11')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('regular-button-custom.chrome.12')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('regular-next-page')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-button-custom.chrome.14')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('regular-button-custom.chrome.14')),
    );
    await tester.pumpAndSettle();
    expect(harness.companion.remoteActions.last.buttonId, 'custom.chrome.14');
  });

  testWidgets(
    'disconnect disables shortcuts pointer and Desktop dictation without HID fallback',
    (tester) async {
      final harness = await mountRegular(tester);
      harness.companion.status.value = CompanionSyncStatus.disconnected;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('regular-connect-desktop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('regular-twelve-key-grid')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('regular-touchpad')), findsNothing);
      final entry = tester.widget<LocalDictationEntryButton>(
        find.byType(LocalDictationEntryButton),
      );
      expect(entry.entryEnabled, isFalse);
      expect(entry.forceDesktopOutput, isTrue);
      expect(harness.companion.remoteActions, isEmpty);
      expect(harness.hid.pressedActions, isEmpty);
    },
  );

  testWidgets('touchpad uses Desktop mouse capability and never local HID', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    final pad = find.byKey(const ValueKey('regular-touchpad'));
    expect(pad, findsOneWidget);
    await tester.tapAt(tester.getCenter(pad));
    await tester.pumpAndSettle();
    expect(harness.companion.pointerInputs.last.kind, PointerInputKind.button);
    expect(harness.hid.steppedActions, isEmpty);
    harness.companion.host.value = connectedCompanionHost;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('regular-touchpad')), findsNothing);
    expect(
      find.byKey(const ValueKey('regular-touchpad-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets(
    'late launch completion cannot select an app on another computer',
    (tester) async {
      final companion = DeferredRegularCompanion();
      final harness = await mountRegular(tester, companion: companion);
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pump();
      expect(companion.remoteActions.single.applicationId, 'chrome');
      companion.host.value = connectedCompanionHost;
      await tester.pump();
      companion.launch.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
            .data,
        'Launchpad',
      );
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
      expect(harness.hid.pressedActions, isEmpty);
    },
  );

  testWidgets(
    'a same-session reconnect invalidates an earlier pending launch',
    (tester) async {
      final companion = DeferredRegularCompanion();
      await mountRegular(tester, companion: companion);
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pump();
      expect(companion.remoteActions.single.applicationId, 'chrome');
      companion.status.value = CompanionSyncStatus.disconnected;
      await tester.pump();
      companion.status.value = CompanionSyncStatus.ready;
      await tester.pump();
      companion.launch.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
            .data,
        'Launchpad',
      );
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'safe areas and large phone text keep four columns without overflow',
    (tester) async {
      final harness = await mountRegular(tester);
      tester.view.padding = const FakeViewPadding(left: 30, right: 18);
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetPadding();
        tester.view.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(regularTestApp(harness));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first = tester.getRect(
        find.byKey(const ValueKey('regular-cell-0')),
      );
      final fourth = tester.getRect(
        find.byKey(const ValueKey('regular-cell-3')),
      );
      final ninth = tester.getRect(
        find.byKey(const ValueKey('regular-cell-8')),
      );
      expect(fourth.top, first.top);
      expect(ninth.top, greaterThan(first.bottom));
    },
  );

  testWidgets('portrait windows gate controls and restore in landscape', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('regular-portrait-gate')), findsOneWidget);
    expect(find.byKey(const ValueKey('regular-twelve-key-grid')), findsNothing);
    expect(harness.companion.remoteActions, isEmpty);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-twelve-key-grid')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
