import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_companion/app_icon_service.dart';
import 'package:lumiakeys_companion/desktop_application_artwork.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _Icons extends NativeAppIconService {
  final pending = <String, Completer<Uint8List?>>{};
  final calls = <String>[];

  @override
  Future<Uint8List?> getNativeIcon(RemoteApplication app) {
    calls.add(app.id);
    return (pending[app.id] ??= Completer<Uint8List?>()).future;
  }
}

const _chrome = RemoteApplication(
  id: 'chrome',
  name: 'Chrome',
  icon: 'chrome',
  executable: 'chrome',
  layoutId: 'app.chrome',
  detected: true,
);
const _firefox = RemoteApplication(
  id: 'firefox',
  name: 'Firefox',
  icon: 'firefox',
  executable: 'firefox',
  layoutId: 'app.firefox',
  detected: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all sixteen canonical brand assets decode within native bounds',
    () async {
      expect(desktopAppIconAssets.length, 17);
      expect(desktopAppIconAssets.values.toSet().length, 16);
      expect(desktopAppIconAssets['codex'], desktopAppIconAssets['chatgpt']);
      expect(desktopAppIconAssets['claude'], 'claude-app.png');
      expect(desktopAppIconAssets['solidworks'], 'solidworks-app.png');
      for (final path in desktopAppIconAssets.values.toSet()) {
        final bytes = await rootBundle.load('assets/app_icons/$path');
        expect(
          validApplicationIconPng(bytes.buffer.asUint8List()),
          isTrue,
          reason: path,
        );
      }
    },
  );

  testWidgets(
    'changing app immediately replaces old native icon with new fallback',
    (tester) async {
      final icons = _Icons();
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      Widget view(RemoteApplication app) => MaterialApp(
        home: DesktopApplicationArtwork(app: app, size: 48, iconService: icons),
      );
      await tester.pumpWidget(view(_chrome));
      icons.pending['chrome']!.complete(bytes);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );

      await tester.pumpWidget(view(_firefox));
      final fallback = tester.widget<Image>(find.byType(Image));
      expect(fallback.image, isA<AssetImage>());
      expect(
        (fallback.image as AssetImage).assetName,
        'assets/app_icons/firefox.png',
      );
      expect(icons.calls, ['chrome', 'firefox']);
      await tester.pumpWidget(view(_firefox));
      expect(icons.calls, ['chrome', 'firefox']);
      icons.pending['firefox']!.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late old-app completion cannot replace current offline artwork',
    (tester) async {
      final icons = _Icons();
      Widget view(RemoteApplication app) => MaterialApp(
        home: DesktopApplicationArtwork(app: app, size: 48, iconService: icons),
      );
      await tester.pumpWidget(view(_chrome));
      await tester.pumpWidget(view(_firefox));
      icons.pending['chrome']!.complete(
        Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/app_icons/firefox.png',
      );
      icons.pending['firefox']!.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
