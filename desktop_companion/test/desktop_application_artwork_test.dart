import 'dart:async';
import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_companion/app_icon_service.dart';
import 'package:lumiakeys_companion/desktop_application_artwork.dart';
import 'package:lumiakeys_companion/icons/builtin_icon_catalog.g.dart';
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
    'all fifty generated offline products decode within native bounds',
    () async {
      expect(desktopAppIconAssets.length, 50);
      expect(desktopAppIconAssets.values.toSet().length, 50);
      expect(desktopAppIconAssets.containsKey('codex'), isFalse);
      expect(builtinIconById('codex'), isNull);
      expect(legacyProtocolIconId('codex'), 'chatgpt');
      expect(desktopAppIconAssets['claude'], 'claude.png');
      expect(desktopAppIconAssets['solidworks'], 'solidworks.png');
      expect(builtinIconById('msedge')?.id, 'edge');
      expect(NativeAppIconService.supportedAppIds.contains('word'), isFalse);
      expect(remoteApplicationIconAppIds.contains('word'), isFalse);
      for (final path in desktopAppIconAssets.values.toSet()) {
        final bytes = await rootBundle.load('assets/app_icons/$path');
        expect(
          validApplicationIconPng(bytes.buffer.asUint8List()),
          isTrue,
          reason: path,
        );
        final image = img.decodePng(bytes.buffer.asUint8List())!;
        expect(image.width, 256);
        expect(image.height, 256);
        final id = path.substring(0, path.length - 4);
        expect(
          sha256.convert(bytes.buffer.asUint8List()).toString(),
          builtinIconById(id)!.sha256,
        );
      }
    },
  );

  testWidgets(
    'extra built-in artwork and explicit legacy fallback need no native launch support',
    (tester) async {
      final icons = _Icons();
      Widget view(RemoteApplication app) => MaterialApp(
        home: DesktopApplicationArtwork(app: app, size: 48, iconService: icons),
      );
      await tester.pumpWidget(
        view(
          const RemoteApplication(
            id: 'word',
            name: 'Word',
            icon: 'word',
            executable: 'Word',
            layoutId: 'app.word',
            detected: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/app_icons/word.png',
      );
      await tester.pumpWidget(
        view(
          const RemoteApplication(
            id: 'codex',
            name: 'Legacy ChatGPT',
            icon: 'chatgpt',
            executable: 'ChatGPT',
            layoutId: 'chatgpt',
            detected: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/app_icons/chatgpt.png',
      );
      expect(icons.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog app artwork stays stable without reading platform-native icons',
    (tester) async {
      final icons = _Icons();
      Widget view(RemoteApplication app) => MaterialApp(
        home: DesktopApplicationArtwork(app: app, size: 48, iconService: icons),
      );
      await tester.pumpWidget(view(_chrome));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/app_icons/chrome.png',
      );

      await tester.pumpWidget(view(_firefox));
      final fallback = tester.widget<Image>(find.byType(Image));
      expect(fallback.image, isA<AssetImage>());
      expect(
        (fallback.image as AssetImage).assetName,
        'assets/app_icons/firefox.png',
      );
      expect(icons.calls, isEmpty);
      await tester.pumpWidget(view(_firefox));
      expect(icons.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom app keeps native icon extraction fallback', (
    tester,
  ) async {
    final icons = _Icons();
    const custom = RemoteApplication(
      id: 'custom-browser',
      name: 'Custom Browser',
      icon: 'custom-browser',
      executable: 'browser.exe',
      layoutId: 'app.custom-browser',
      detected: true,
    );
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopApplicationArtwork(
          app: custom,
          size: 48,
          iconService: icons,
        ),
      ),
    );
    expect(icons.calls, ['custom-browser']);
    icons.pending['custom-browser']!.complete(bytes);
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
  });

  testWidgets(
    'late old-app completion cannot replace current offline artwork',
    (tester) async {
      final icons = _Icons();
      const first = RemoteApplication(
        id: 'custom-one',
        name: 'Custom One',
        icon: 'custom-one',
        executable: 'one.exe',
        layoutId: 'app.custom-one',
        detected: true,
      );
      const second = RemoteApplication(
        id: 'custom-two',
        name: 'Custom Two',
        icon: 'custom-two',
        executable: 'two.exe',
        layoutId: 'app.custom-two',
        detected: true,
      );
      Widget view(RemoteApplication app) => MaterialApp(
        home: DesktopApplicationArtwork(app: app, size: 48, iconService: icons),
      );
      await tester.pumpWidget(view(first));
      await tester.pumpWidget(view(second));
      icons.pending['custom-one']!.complete(
        Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
      );
      await tester.pump();
      expect(find.byIcon(Icons.apps), findsOneWidget);
      icons.pending['custom-two']!.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
