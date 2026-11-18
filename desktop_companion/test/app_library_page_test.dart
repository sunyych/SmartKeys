import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/app_library_page.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

void main() {
  testWidgets(
    'Desktop App detail previews actual OS and installs an explicit copy',
    (tester) async {
      final c = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: Discovery(),
        libraryOperatingSystem: 'windows',
      );
      await c.initialize();
      try {
        await tester.pumpWidget(
          MaterialApp(home: DesktopAppLibraryPage(controller: c)),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('desktop-library-search')),
          'Chrome',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('desktop-library-app-chrome')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('desktop-library-install')));
        await tester.pumpAndSettle();
        expect(
          c.manifest.profiles.where((p) => p.sourceAppId == 'chrome'),
          hasLength(1),
        );
        expect(
          find.textContaining('App icon and shortcuts saved'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
  testWidgets(
    'Safari is mac-only and another OS cannot install on this Windows host',
    (tester) async {
      final c = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: Discovery(),
        libraryOperatingSystem: 'windows',
      );
      await c.initialize();
      try {
        await tester.pumpWidget(
          MaterialApp(home: DesktopAppLibraryPage(controller: c)),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('desktop-library-search')),
          'Safari',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('desktop-library-app-safari')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('desktop-library-os')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('macOS').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('desktop-library-app-safari')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('desktop-library-install')),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Command + N'), findsWidgets);
        expect(find.textContaining('META +'), findsNothing);
        expect(find.textContaining('Desktop app · v'), findsOneWidget);
        expect(c.manifest.profiles.where((p) => p.isLibraryProfile), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
}
