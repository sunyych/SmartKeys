import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_companion/app_icon_service.dart';
import 'package:lumiakeys_companion/windows_desktop_backend.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _RecordingIconRegistry extends Fake implements WindowsDesktopBackend {
  _RecordingIconRegistry(this.entry);

  final WindowsRegisteredAppPath entry;
  int reads = 0;

  @override
  Future<WindowsRegistryInventory> readRegistry() async {
    reads++;
    return WindowsRegistryInventory(installedNames: [], appPaths: [entry]);
  }
}

Future<File> _fixtureExecutable(String name) async {
  final root = await Directory.systemTemp.createTemp('lumiakeys-icon-route-');
  final file = File('${root.path}${Platform.pathSeparator}$name');
  addTearDown(() async {
    if (await file.exists()) await file.delete();
    await root.delete();
  });
  return file.writeAsBytes([0x4d, 0x5a]);
}

const _chrome = RemoteApplication(
  id: 'chrome',
  name: 'Google Chrome',
  icon: 'chrome',
  executable: 'Google Chrome',
  layoutId: 'app.chrome',
  detected: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/rust-desktop-registered-icon');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
  late List<MethodCall> requests;

  setUp(() {
    requests = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      requests.add(call);
      return png;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'Rust icon lookup uses the local registered alias instead of manifest text',
    () async {
      final local = await _fixtureExecutable('chrome.exe');
      final native = _RecordingIconRegistry(
        WindowsRegisteredAppPath(name: 'CHROME.EXE', path: local.path),
      );
      var fallbackCalls = 0;
      final service = NativeAppIconService(
        platformOverride: TargetPlatform.windows,
        installedChannel: channel,
        windowsDesktopBackend: native,
        processRunner: (_, _, _) async {
          fallbackCalls++;
          return ProcessResult(1, 2, '', '');
        },
      );

      final icon = await service.getNativeIcon(
        _chrome.copyWith(executable: r'C:\Fixture\Unrelated.exe'),
      );
      expect(icon, orderedEquals(png));
      expect(native.reads, 1);
      expect(fallbackCalls, 0);
      expect(requests.single.method, 'icon');
      expect(requests.single.arguments, {
        'kind': 'windowsExecutable',
        'locator': local.path,
      });
    },
    skip: !Platform.isWindows,
  );

  test(
    'an unrelated registry path never reaches native icon extraction',
    () async {
      final foreign = await _fixtureExecutable('foreign.exe');
      final native = _RecordingIconRegistry(
        WindowsRegisteredAppPath(name: 'foreign.exe', path: foreign.path),
      );
      final fallbackCommands = <String>[];
      final service = NativeAppIconService(
        platformOverride: TargetPlatform.windows,
        installedChannel: channel,
        windowsDesktopBackend: native,
        processRunner: (executable, arguments, _) async {
          expect(executable, 'powershell.exe');
          fallbackCommands.add(arguments.last);
          return ProcessResult(1, 2, '', '');
        },
      );

      final icon = await service.getNativeIcon(
        _chrome.copyWith(executable: foreign.path),
      );
      expect(icon, isNull);
      expect(native.reads, 1);
      expect(requests, isEmpty);
      expect(fallbackCommands, [
        NativeAppIconService.windowsIconCommand('chrome'),
      ]);
      expect(fallbackCommands.single, isNot(contains(foreign.path)));
    },
    skip: !Platform.isWindows,
  );
}
