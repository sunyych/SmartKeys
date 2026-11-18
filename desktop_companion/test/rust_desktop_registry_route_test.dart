import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/installed_app_discovery.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';
import 'package:lumiakeys_companion/windows_desktop_backend.dart';

class _RecordingRegistry extends Fake implements WindowsDesktopBackend {
  _RecordingRegistry(this.inventory);

  final WindowsRegistryInventory inventory;
  int calls = 0;

  @override
  Future<WindowsRegistryInventory> readRegistry() async {
    calls++;
    return inventory;
  }
}

class _UnavailableRegistry extends Fake implements WindowsDesktopBackend {
  int calls = 0;

  @override
  Future<WindowsRegistryInventory> readRegistry() async {
    calls++;
    throw StateError('Synthetic native registry read failure');
  }
}

const _shellRows = [
  {
    'name': 'Fixture Windows App',
    'kind': 'windowsAppId',
    'identity': 'aumid:Fixture.Test_8wekyb3d8bbwe!App',
    'locator': 'Fixture.Test_8wekyb3d8bbwe!App',
  },
  {
    'name': 'Fixture Windows Link',
    'kind': 'windowsShortcut',
    'identity': r'startmenu:1:\fixture-link.lnk',
    'locator': r'C:\ProgramData\Start Menu\Fixture-Link.lnk',
    'executablePath': r'C:\Fixtures\LinkTarget.exe',
  },
];

void main() {
  test(
    'native App Paths preserve legacy stable IDs and local launch fields',
    () async {
      const executable = r'C:\Program Files\Fixture Editor\Editor.EXE';
      final identity = 'apppath:${executable.toLowerCase()}';
      final legacy = PlatformInstalledApplicationDiscovery(
        platform: TargetPlatform.windows,
        runner: (_, _) async => ProcessResult(
          1,
          0,
          jsonEncode([
            ..._shellRows,
            {
              'name': 'Editor.exe',
              'kind': 'windowsExecutable',
              'identity': identity,
              'locator': executable,
              'executablePath': executable,
            },
          ]),
          '',
        ),
      );
      final native = _RecordingRegistry(
        WindowsRegistryInventory(
          installedNames: ['Fixture Uninstall Metadata'],
          appPaths: [
            WindowsRegisteredAppPath(name: 'Editor.exe', path: executable),
          ],
        ),
      );
      var shellCalls = 0;
      final migrated = PlatformInstalledApplicationDiscovery(
        platform: TargetPlatform.windows,
        windowsDesktopBackend: native,
        runner: (executable, arguments) async {
          expect(executable, 'powershell.exe');
          expect(arguments, contains('-Command'));
          shellCalls++;
          return ProcessResult(1, 0, jsonEncode(_shellRows), '');
        },
      );

      final before = await legacy.discover();
      final after = await migrated.discover();
      expect(
        after.map((target) => target.toLocalJson()),
        unorderedEquals(before.map((target) => target.toLocalJson())),
      );
      expect(shellCalls, 1);
      expect(native.calls, 1);

      final discovered = after.singleWhere(
        (target) => target.kind == InstalledLaunchKind.windowsExecutable,
      );
      expect(
        discovered.id,
        installedApplicationId(InstalledLaunchKind.windowsExecutable, identity),
      );
      expect(discovered.locator, executable);
      expect(discovered.executablePath, executable);
      expect(
        after.map((target) => target.name),
        isNot(contains('Fixture Uninstall Metadata')),
      );
    },
  );

  test(
    'failed Rust registry read falls back to full legacy discovery once',
    () async {
      final native = _UnavailableRegistry();
      final scripts = <String>[];
      final discovery = PlatformInstalledApplicationDiscovery(
        platform: TargetPlatform.windows,
        windowsDesktopBackend: native,
        runner: (_, arguments) async {
          scripts.add(arguments.last);
          return ProcessResult(1, 0, jsonEncode(_shellRows), '');
        },
      );

      final discovered = await discovery.discover();

      expect(native.calls, 1);
      expect(scripts, [
        PlatformInstalledApplicationDiscovery.windowsInventoryScript,
      ]);
      expect(discovered.map((target) => target.kind), [
        InstalledLaunchKind.windowsAppId,
        InstalledLaunchKind.windowsShortcut,
      ]);
    },
  );

  test(
    'Shell scan failure after Rust success preserves discovery failure',
    () async {
      final native = _RecordingRegistry(
        WindowsRegistryInventory(installedNames: [], appPaths: []),
      );
      var shellCalls = 0;
      final discovery = PlatformInstalledApplicationDiscovery(
        platform: TargetPlatform.windows,
        windowsDesktopBackend: native,
        runner: (_, _) async {
          shellCalls++;
          return ProcessResult(1, 1, '', 'Synthetic shell failure');
        },
      );

      await expectLater(
        discovery.discover(),
        throwsA(isA<FileSystemException>()),
      );
      expect(native.calls, 1);
      expect(shellCalls, 1);
    },
  );
}
