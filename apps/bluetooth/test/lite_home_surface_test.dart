import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakey_bluetooth_lite/lite_editors.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';
import 'package:lumiakey_bluetooth_lite/local_settings.dart';
import 'package:lumiakey_bluetooth_lite/offline_touchpad.dart';
import 'lite_home_fixture.dart';

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  for (final variant in [
    (const Size(844, 390), 1.0, EdgeInsets.zero),
    (const Size(1180, 820), 1.0, const EdgeInsets.fromLTRB(24, 20, 24, 20)),
    (const Size(844, 390), 1.6, const EdgeInsets.fromLTRB(20, 0, 20, 20)),
    (const Size(740, 360), 1.5, const EdgeInsets.fromLTRB(16, 0, 16, 20)),
  ]) {
    testWidgets(
      'twelve-key landscape geometry ${variant.$1} scale ${variant.$2}',
      (tester) async {
        final fixture = LiteHomeFixture();
        await fixture.initialize();
        try {
          await fixture.mount(
            tester,
            size: variant.$1,
            textScale: variant.$2,
            padding: variant.$3,
          );
          expect(tester.takeException(), isNull);
          expect(key('lite-twelve-key-grid'), findsOneWidget);
          for (var index = 0; index < 12; index++) {
            expect(key('lite-cell-$index'), findsOneWidget);
            expect(
              tester.getRect(key('lite-cell-$index')).height,
              greaterThan(35),
            );
          }
          final first = tester.getRect(key('lite-cell-0'));
          final fourth = tester.getRect(key('lite-cell-3'));
          final fifth = tester.getRect(key('lite-cell-4'));
          expect(first.top, fourth.top);
          expect(first.left, fifth.left);
          expect(fifth.top, greaterThan(first.bottom));
          final grid = tester.getRect(key('lite-twelve-key-grid'));
          final touchpad = tester.getRect(find.byType(OfflineTouchpad));
          expect(grid.right, lessThan(touchpad.left));
          expect(grid.width / touchpad.width, closeTo(2, .15));
          final brand = tester.getRect(key('lite-brand-icon'));
          final label = tester.getRect(key('lite-brand-label'));
          expect(brand.bottom, lessThanOrEqualTo(label.top));
          expect(label.bottom, lessThan(grid.top + 45));
          final header = tester.getRect(key('lite-header'));
          final controls = tester.getRect(key('lite-header-controls'));
          expect(controls.center.dx, closeTo(header.center.dx, 1));
          expect(controls.bottom, lessThanOrEqualTo(grid.top));
          expect(
            tester.widget<Text>(key('lite-clock')).data,
            matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')),
          );
          expect(find.byIcon(Icons.mic), findsNothing);
          expect(find.textContaining('KVM'), findsNothing);
          expect(find.textContaining('Desktop Companion'), findsNothing);
          await tester.tap(key('lite-nav-general'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            fixture.inputs,
            isEmpty,
            reason: 'Selecting a local page cannot send HID',
          );
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }

  testWidgets('named unconfigured cards open the editor without input', (
    tester,
  ) async {
    final fixture = LiteHomeFixture();
    await fixture.initialize();
    try {
      await fixture.mount(tester);
      expect(fixture.controller.selectedProfileId, isNull);
      expect(
        fixture.controller.launcherSlots
            .take(2)
            .every((slot) => !slot.configured),
        true,
      );
      await tester.tap(key('lite-launch-0'));
      await tester.pumpAndSettle();
      expect(find.byType(LiteLaunchSlotEditor), findsOneWidget);
      expect(fixture.controller.canSendInput, false);
      expect(fixture.inputs, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(fixture.controller.canSendInput, true);
      await tester.tap(key('lite-nav-profile-chatgpt'));
      await tester.pumpAndSettle();
      expect(fixture.controller.selectedProfileId, 'chatgpt');
      expect(fixture.inputs, isEmpty);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'configured launch sends only its saved chord and opens linked profile',
    (tester) async {
      final fixture = LiteHomeFixture();
      await fixture.initialize(slots: configuredSurfaceSlots());
      try {
        await fixture.mount(tester);
        await tester.tap(key('lite-launch-0'));
        await tester.pumpAndSettle();
        expect(fixture.inputs, hasLength(1));
        expect(fixture.inputs.single.arguments, {
          'type': 'keyboard',
          'keyCode': 'G',
          'modifiers': ['LEFT_CTRL', 'LEFT_ALT'],
          'expectedHostAddress': 'AA:BB:CC:DD:EE:01',
        });
        expect(fixture.controller.selectedProfileId, 'chatgpt');
        expect(
          tester.widget<Text>(key('lite-workspace-title')).data,
          'ChatGPT',
        );
        await tester.tap(key('lite-shortcut-0'));
        await tester.pumpAndSettle();
        expect(fixture.inputs, hasLength(2));
        expect((fixture.inputs.last.arguments as Map)['keyCode'], 'N');
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('failed launch does not claim success or change profile', (
    tester,
  ) async {
    final fixture = LiteHomeFixture();
    await fixture.initialize(slots: configuredSurfaceSlots());
    fixture.failInput = true;
    try {
      await fixture.mount(tester);
      await tester.tap(key('lite-launch-0'));
      await tester.pumpAndSettle();
      expect(fixture.inputs, hasLength(1));
      expect(fixture.controller.selectedProfileId, isNull);
      expect(key('lite-home-error'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets('a launch without linked profile stays on Launchpad', (
    tester,
  ) async {
    final fixture = LiteHomeFixture();
    await fixture.initialize(slots: configuredSurfaceSlots(linked: false));
    try {
      await fixture.mount(tester);
      await tester.tap(key('lite-launch-0'));
      await tester.pumpAndSettle();
      expect(fixture.inputs, hasLength(1));
      expect(fixture.controller.selectedProfileId, isNull);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'fifteen saved shortcuts remain on two pages and cancel old pointer callbacks',
    (tester) async {
      final fixture = LiteHomeFixture();
      final legacy = LocalProfile(
        id: 'legacy',
        name: 'My saved shortcuts',
        shortcuts: List.generate(
          15,
          (index) => LocalShortcut(
            title: 'My saved action number ${index + 1}',
            keyCode: '${index % 10}',
            modifiers: const [],
          ),
        ),
      );
      await fixture.initialize(profiles: [...defaultLocalProfiles(), legacy]);
      try {
        await fixture.mount(tester, textScale: 1.5);
        fixture.controller.selectProfile('legacy');
        await tester.pumpAndSettle();
        final stalePad = tester.widget<OfflineTouchpad>(
          find.byType(OfflineTouchpad),
        );
        final oldEpoch = fixture.controller.inputEpoch;
        await tester.tap(key('lite-next-page'));
        stalePad.onMove(const Offset(30, 10));
        stalePad.onPrimaryTap();
        await tester.pumpAndSettle();
        expect(fixture.controller.inputEpoch, greaterThan(oldEpoch));
        expect(fixture.inputs, isEmpty);
        expect(key('lite-shortcut-12'), findsOneWidget);
        expect(key('lite-shortcut-14'), findsOneWidget);
        await tester.tap(key('lite-shortcut-14'));
        await tester.pumpAndSettle();
        expect((fixture.inputs.single.arguments as Map)['keyCode'], '4');
        expect(fixture.controller.profiles.last.shortcuts, hasLength(15));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'settings and its real icon library route cancel input until returning home',
    (tester) async {
      final fixture = LiteHomeFixture();
      await fixture.initialize(slots: configuredSurfaceSlots());
      try {
        await fixture.mount(tester);
        final stalePad = tester.widget<OfflineTouchpad>(
          find.byType(OfflineTouchpad),
        );
        await tester.tap(key('lite-settings'));
        stalePad.onPrimaryTap();
        await tester.pumpAndSettle();
        expect(find.byType(LiteSettingsScreen), findsOneWidget);
        expect(fixture.controller.canSendInput, false);
        expect(await fixture.controller.sendConsumer('MUTE'), false);
        await tester.ensureVisible(key('lite-icon-library-entry'));
        await tester.tap(key('lite-icon-library-entry'));
        await tester.pumpAndSettle();
        expect(find.byType(LiteIconLibraryScreen), findsOneWidget);
        expect(fixture.inputs, isEmpty);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(fixture.controller.canSendInput, false);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(fixture.controller.canSendInput, true);
        await tester.tap(key('lite-system-MUTE'));
        await tester.pumpAndSettle();
        expect((fixture.inputs.single.arguments as Map)['value'], 'MUTE');
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'disconnected and portrait controls send no input and recover safely',
    (tester) async {
      final fixture = LiteHomeFixture();
      await fixture.initialize(
        slots: configuredSurfaceSlots(),
        connected: false,
      );
      try {
        await fixture.mount(tester);
        expect(
          tester.widget<OfflineTouchpad>(find.byType(OfflineTouchpad)).enabled,
          false,
        );
        await tester.tap(key('lite-launch-0'));
        await tester.tapAt(tester.getCenter(key('mouse-touchpad')));
        await tester.pumpAndSettle();
        expect(fixture.inputs, isEmpty);
        await fixture.mount(tester, size: const Size(390, 844));
        expect(key('lite-portrait-gate'), findsOneWidget);
        expect(find.byType(OfflineTouchpad), findsNothing);
        expect(await fixture.controller.sendConsumer('MUTE'), false);
        expect(fixture.inputs, isEmpty);
        await fixture.mount(tester);
        expect(key('lite-twelve-key-grid'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}
