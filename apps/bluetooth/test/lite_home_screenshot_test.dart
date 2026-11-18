import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakey_bluetooth_lite/icons/builtin_icon_catalog.g.dart';
import 'package:lumiakey_bluetooth_lite/local_launcher.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';
import 'lite_home_fixture.dart';
import 'screenshot_support.dart';

void main() {
  testWidgets('renders current Bluetooth Lite landscape Home gallery', (
    tester,
  ) async {
    await tester.runAsync(ScreenshotSupport.prepareFonts);
    final shots = ScreenshotSupport(tester);
    final boundary = GlobalKey();
    LiteHomeFixture? active;
    Future<void> show({
      Size size = const Size(844, 390),
      bool connected = true,
      List<LocalLaunchSlot>? slots,
      List<LocalProfile>? profiles,
      double scale = 1,
    }) async {
      if (active != null) await active!.close(tester);
      active = LiteHomeFixture();
      await active!.initialize(
        slots: slots,
        profiles: profiles,
        connected: connected,
      );
      await active!.mount(
        tester,
        size: size,
        textScale: scale,
        boundary: boundary,
      );
      final context = tester.element(
        find.byKey(const ValueKey('lite-home')).evaluate().isNotEmpty
            ? find.byKey(const ValueKey('lite-home'))
            : find.byKey(const ValueKey('lite-portrait-gate')),
      );
      await tester.runAsync(() async {
        await Future.wait([
          precacheImage(
            const ResizeImage(
              AssetImage('assets/app_icon/app_icon_source.png'),
              width: 96,
            ),
            context,
          ),
          for (final icon in builtinIconCatalog)
            precacheImage(AssetImage(icon.assetPath), context),
        ]);
      });
      await tester.pumpAndSettle();
    }

    Future<void> capture(
      String id,
      String title, {
      bool portrait = false,
    }) async {
      await tester.pumpAndSettle();
      await shots.capture(
        id: id,
        title: title,
        orientation: portrait ? 'portrait' : 'landscape',
        notes:
            'Bluetooth Lite 1.2.0+3 current production Home, fake local stores and mock Android HID only. No Desktop, KVM, voice, network, or physical input.',
        boundaryKey: boundary,
      );
    }

    Future<void> select(String id) async {
      active!.controller.selectProfile(id);
      await tester.pumpAndSettle();
    }

    try {
      await show();
      await capture(
        'lite-home-launchpad-default',
        'Lite Launchpad: named slots require local configuration',
      );
      await show(slots: configuredSurfaceSlots());
      await capture(
        'lite-home-launchpad-configured',
        'Lite connected Launchpad with saved keyboard bindings',
      );
      await select('general');
      await capture(
        'lite-home-general',
        'Lite General twelve keyboard and media controls',
      );
      await select('chatgpt');
      await capture('lite-home-chatgpt', 'Lite ChatGPT local shortcut page');
      await select('chrome');
      await capture('lite-home-chrome', 'Lite Chrome local shortcut page');
      final legacy = LocalProfile(
        id: 'legacy',
        name: 'My saved shortcuts',
        iconId: 'unregistered-brand',
        shortcuts: List.generate(
          15,
          (index) => LocalShortcut(
            title: 'Saved action ${index + 1}',
            keyCode: '${index % 10}',
            modifiers: const [],
          ),
        ),
      );
      await show(profiles: [...defaultLocalProfiles(), legacy]);
      await select('legacy');
      await tester.tap(find.byKey(const ValueKey('lite-next-page')));
      await tester.pumpAndSettle();
      await capture(
        'lite-home-legacy-page-two',
        'Lite preserves all fifteen saved shortcuts using pages',
      );
      await show(slots: configuredSurfaceSlots(), size: const Size(1180, 820));
      await capture(
        'lite-home-tablet-launchpad',
        'Lite tablet: same twelve-slot landscape surface',
      );
      await select('general');
      await capture(
        'lite-home-tablet-general',
        'Lite tablet General and persistent touchpad',
      );
      await show(scale: 1.6);
      await select('general');
      await capture(
        'lite-home-large-text',
        'Lite phone General with large text',
      );
      await show(slots: configuredSurfaceSlots(), connected: false);
      await capture(
        'lite-home-disconnected',
        'Lite disconnected input disabled; Bluetooth settings available',
      );
      await show(size: const Size(390, 844));
      await capture(
        'lite-home-portrait-gate',
        'Lite portrait gate sends no input',
        portrait: true,
      );
      await show(slots: configuredSurfaceSlots());
      active!.failInput = true;
      await tester.tap(find.byKey(const ValueKey('lite-launch-0')));
      await tester.pumpAndSettle();
      await capture(
        'lite-home-launch-failed',
        'Lite failed launch remains on Launchpad with a recoverable error',
      );
    } finally {
      if (active != null) await active!.close(tester);
      shots.resetViewport();
    }
  });
}
