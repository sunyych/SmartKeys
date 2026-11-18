import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/app_icon_service.dart';

final iconFixture = Uint8List.fromList(
  img.encodePng(img.Image(width: 2, height: 2)),
);
const chromeFixture = RemoteApplication(
  id: 'chrome',
  name: 'Chrome',
  icon: 'chrome',
  executable: 'Google Chrome',
  layoutId: 'app.chrome',
  detected: true,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/app_icons');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('PNG validation checks full decoding, dimensions and byte bounds', () {
    expect(validApplicationIconPng(iconFixture), isTrue);
    expect(
      validApplicationIconPng(
        Uint8List.fromList(iconFixture.take(32).toList()),
      ),
      isFalse,
    );
    expect(validApplicationIconPng(Uint8List(65537)), isFalse);
    final huge = Uint8List.fromList(iconFixture);
    ByteData.sublistView(huge).setUint32(16, 513);
    expect(validApplicationIconPng(huge), isFalse);
  });
  test(
    'mac native results are validated and simultaneous requests coalesce',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            return iconFixture;
          });
      final service = NativeAppIconService(
        channel: channel,
        platformOverride: TargetPlatform.macOS,
      );
      final results = await Future.wait([
        service.getNativeIcon(chromeFixture),
        service.getNativeIcon(chromeFixture),
      ]);
      expect(results, everyElement(orderedEquals(iconFixture)));
      expect(calls, 1);
      expect(await service.getNativeIcon(chromeFixture), iconFixture);
      expect(calls, 1);
    },
  );
  test(
    'unknown IDs and invalid executable metadata never invoke native extraction',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            return iconFixture;
          });
      final service = NativeAppIconService(
        channel: channel,
        platformOverride: TargetPlatform.macOS,
      );
      expect(
        await service.getNativeIcon(
          const RemoteApplication(
            id: 'unknown',
            name: 'Unknown',
            icon: 'app',
            executable: 'unknown',
            layoutId: 'app.chrome',
          ),
        ),
        isNull,
      );
      expect(
        await service.getNativeIcon(
          chromeFixture.copyWith(executable: 'bad\u0000path'),
        ),
        isNull,
      );
      expect(calls, 0);
    },
  );
  test(
    'malformed native data and timeouts are optional failures, not app failures',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          );
      expect(
        await NativeAppIconService(
          channel: channel,
          platformOverride: TargetPlatform.macOS,
        ).getNativeIcon(chromeFixture),
        isNull,
      );
      final pending = Completer<Uint8List?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) => pending.future);
      expect(
        await NativeAppIconService(
          channel: channel,
          platformOverride: TargetPlatform.macOS,
          timeout: const Duration(milliseconds: 20),
        ).getNativeIcon(chromeFixture),
        isNull,
      );
      pending.complete();
    },
  );
  test(
    'Windows extraction only passes a registered app ID to a bounded fixed script',
    () async {
      late List<String> arguments;
      final service = NativeAppIconService(
        platformOverride: TargetPlatform.windows,
        processRunner: (exe, args, limit) async {
          expect(exe, 'powershell.exe');
          expect(limit, const Duration(seconds: 3));
          arguments = args;
          return ProcessResult(1, 0, base64Encode(iconFixture), '');
        },
      );
      expect(
        await service.getNativeIcon(
          chromeFixture.copyWith(
            executable: 'https://untrusted.invalid/arbitrary.exe',
          ),
        ),
        iconFixture,
      );
      expect(arguments.last.trimRight(), endsWith("} 'chrome'"));
      expect(arguments.length, arguments.indexOf('-Command') + 2);
      expect(arguments.join(' '), isNot(contains('untrusted.invalid')));
      expect(arguments, containsAll(['-WindowStyle', 'Hidden']));
    },
  );
  test(
    'Linux reads bounded matching desktop metadata, not near-name aliases',
    () async {
      final temp = await Directory.systemTemp.createTemp('lumia-icons-');
      final absoluteTemp = await temp.resolveSymbolicLinks();
      final systemTemp = await Directory.systemTemp.resolveSymbolicLinks();
      expect(
        absoluteTemp.startsWith('$systemTemp${Platform.pathSeparator}'),
        isTrue,
      );
      addTearDown(() async {
        if (await temp.resolveSymbolicLinks() == absoluteTemp) {
          await temp.delete(recursive: true);
        }
      });
      final png = File('${temp.path}/hicolor/128x128/apps/chrome.png');
      await png.parent.create(recursive: true);
      await png.writeAsBytes(iconFixture);
      await File('${temp.path}/chrome.desktop').writeAsString(
        '[Desktop Entry]\nName=Google Chrome\nExec=google-chrome %U\nIcon=chrome\n',
      );
      final service = NativeAppIconService(
        platformOverride: TargetPlatform.linux,
        linuxDesktopDirectories: [temp.path],
        linuxIconDirectories: [temp.path],
      );
      expect(await service.getNativeIcon(chromeFixture), iconFixture);
      const code = RemoteApplication(
        id: 'vscode',
        name: 'VSCode',
        icon: 'code',
        executable: 'code',
        layoutId: 'app.vscode',
      );
      await File('${temp.path}/decoder.desktop').writeAsString(
        '[Desktop Entry]\nName=Decoder\nExec=decoder\nIcon=chrome\n',
      );
      expect(await service.getNativeIcon(code), isNull);
    },
  );
}
