import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/app_icon_service.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';

void main() {
  test(
    'real PowerShell receives the native icon app ID inside its script scope',
    () async {
      final command = NativeAppIconService.windowsIconCommand('chrome');
      final probe = command.replaceFirst(
        r'$executables = switch ($appId)',
        r'Write-Output $appId; return; $executables = switch ($appId)',
      );
      final result = await runBoundedDesktopProcess('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        probe,
      ], const Duration(seconds: 10));
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString().trim(), 'chrome');
    },
    skip: !Platform.isWindows,
  );
  test(
    'real PowerShell retains brightness through the pipeline without changing displays',
    () async {
      final command = DesktopActions.windowsBrightnessCommand(73);
      final probe = command
          .replaceFirst(
            'Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods',
            '@(1,2)',
          )
          .replaceFirst(
            r'Invoke-CimMethod -InputObject $_ -MethodName WmiSetBrightness -Arguments @{Timeout=1;Brightness=$brightness} | Out-Null',
            r'Write-Output $brightness',
          );
      expect(probe, isNot(contains('Cim')));
      expect(probe, isNot(contains('Wmi')));
      final result = await runBoundedDesktopProcess('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        probe,
      ], const Duration(seconds: 10));
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString().trim().split(RegExp(r'\s+')), [
        '73',
        '73',
      ]);
      expect(
        () => DesktopActions.windowsBrightnessCommand(101),
        throwsFormatException,
      );
    },
    skip: !Platform.isWindows,
  );
  test(
    'installed Chrome native artwork is extracted by the real Windows pipeline',
    () async {
      final installed = await runBoundedDesktopProcess('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$p='HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'; if(Test-Path $p){Write-Output ((Get-Item $p).GetValue(''))}",
      ], const Duration(seconds: 10));
      if (installed.stdout.toString().trim().isEmpty) {
        markTestSkipped('Chrome is not registered on this test host.');
        return;
      }
      final bytes =
          await NativeAppIconService(
            platformOverride: TargetPlatform.windows,
          ).getNativeIcon(
            const RemoteApplication(
              id: 'chrome',
              name: 'Chrome',
              icon: 'chrome',
              executable: 'Google Chrome',
              layoutId: 'app.chrome',
              detected: true,
            ),
          );
      expect(bytes, isNotNull);
      expect(validApplicationIconPng(bytes!), isTrue);
      final target = Directory(
        Platform.environment['SMARTKEYS_ICON_EVIDENCE_DIR'] ??
            '../build/handoff-1.5.0/native-icons',
      );
      await target.create(recursive: true);
      await File('${target.path}/chrome-native.png').writeAsBytes(bytes);
    },
    skip: !Platform.isWindows,
  );
}
