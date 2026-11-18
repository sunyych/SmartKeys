import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/installed_app_discovery.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Windows inventory includes hundreds of app IDs shortcuts and registered executables',
    () async {
      final calls = <List<String>>[];
      final rows = [
        for (var i = 0; i < 240; i++)
          {
            'name': 'Application $i',
            'kind': 'windowsAppId',
            'identity': 'aumid:Package$i!App',
            'locator': 'Package$i!App',
          },
        {
          'name': 'Shortcut App',
          'kind': 'windowsShortcut',
          'identity': 'startmenu:1:app.lnk',
          'locator': r'C:\ProgramData\Start Menu\App.lnk',
          'executablePath': r'C:\Program Files\App\App.exe',
        },
      ];
      final provider = PlatformInstalledApplicationDiscovery(
        platform: TargetPlatform.windows,
        runner: (exe, args) async {
          calls.add(args);
          expect(exe, 'powershell.exe');
          return ProcessResult(1, 0, jsonEncode(rows), '');
        },
      );
      final apps = await provider.discover();
      expect(apps, hasLength(241));
      expect(apps.map((app) => app.id).toSet(), hasLength(241));
      expect(apps.last.kind, InstalledLaunchKind.windowsShortcut);
      expect(calls.single, contains('Hidden'));
    },
  );
  test(
    'conflicting identity hostile metadata unsupported kinds and excessive output are rejected',
    () {
      final row = {
        'name': 'App',
        'kind': 'windowsShortcut',
        'identity': 'same',
        'locator': r'C:\App\a.lnk',
      };
      expect(
        () => PlatformInstalledApplicationDiscovery.parseInventory(
          jsonEncode([
            row,
            {...row, 'locator': r'C:\App\b.lnk'},
          ]),
          TargetPlatform.windows,
        ),
        throwsFormatException,
      );
      expect(
        () => PlatformInstalledApplicationDiscovery.parseInventory(
          jsonEncode([
            {...row, 'kind': 'shellCommand', 'locator': 'cmd /c evil'},
          ]),
          TargetPlatform.windows,
        ),
        throwsFormatException,
      );
      expect(
        () => PlatformInstalledApplicationDiscovery.parseInventory(
          jsonEncode([
            {...row, 'name': 'App\ncommand'},
          ]),
          TargetPlatform.windows,
        ),
        throwsFormatException,
      );
      expect(
        () => PlatformInstalledApplicationDiscovery.parseInventory(
          jsonEncode(List.filled(2001, row)),
          TargetPlatform.windows,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Linux discovery delegates inventory to GIO without parsing or executing Exec strings',
    () async {
      const channel = MethodChannel('test/installed-apps');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'discover');
            expect(call.arguments, isNull);
            calls++;
            return [
              {
                'identity': 'org.example.App.desktop',
                'name': 'Example',
                'locator': '/usr/share/applications/org.example.App.desktop',
                'startupWMClass': 'example',
              },
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final apps = await PlatformInstalledApplicationDiscovery(
        platform: TargetPlatform.linux,
        channel: channel,
        runner: (_, _) async => throw StateError('No process parsing on Linux'),
      ).discover();
      expect(calls, 1);
      expect(apps.single.kind, InstalledLaunchKind.linuxDesktopEntry);
      expect(apps.single.startupWMClass, 'example');
    },
  );
  test(
    'mac bundle identities and icon hints are data only and do not grant known app IDs',
    () {
      final apps = PlatformInstalledApplicationDiscovery.parseInventory(
        jsonEncode([
          {
            'name': 'Google Chrome',
            'identity': 'bundle:com.google.Chrome',
            'locator': '/Applications/Google Chrome.app',
            'executablePath':
                '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
          },
        ]),
        TargetPlatform.macOS,
      );
      expect(apps.single.id, startsWith('installed.'));
      expect(apps.single.id, isNot('chrome'));
      expect(apps.single.iconKey, 'chrome');
    },
  );
}
