import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _Runner implements DesktopProcessRunner {
  _Runner({this.results = const {}});

  final Map<int, ProcessResult> results;
  final calls = <({String executable, List<String> arguments})>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final index = calls.length;
    calls.add((executable: executable, arguments: List.of(arguments)));
    return results[index] ?? ProcessResult(1, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) async =>
      throw StateError('The test cannot start a detached OS process');
}

DesktopActions _actions(
  _Runner runner, [
  TargetPlatform platform = TargetPlatform.windows,
]) => DesktopActions(
  platformOverride: platform,
  runner: runner,
  environment: const {},
);

void main() {
  test('Windows dark mode restores the captured brightness once', () async {
    final runner = _Runner(results: {0: ProcessResult(1, 0, '53\r\n', '')});
    final actions = _actions(runner);
    await actions.setComputerDark(true);
    await actions.setComputerDark(false);
    await actions.setComputerDark(false);

    expect(
      runner.calls.map((call) => call.executable),
      List.filled(4, 'powershell.exe'),
    );
    expect(runner.calls.first.arguments.last, contains('CurrentBrightness'));
    expect(runner.calls.skip(1).map((call) => call.arguments.last), [
      DesktopActions.windowsBrightnessCommand(0),
      DesktopActions.windowsBrightnessCommand(53),
      DesktopActions.windowsBrightnessCommand(70),
    ]);
  });

  test(
    'Windows dark mode can exit after an unavailable brightness read',
    () async {
      final runner = _Runner(
        results: {0: ProcessResult(1, 1, '', 'Unavailable')},
      );
      final actions = _actions(runner);
      await actions.setComputerDark(true);
      await actions.setComputerDark(false);
      expect(runner.calls.skip(1).map((call) => call.arguments.last), [
        DesktopActions.windowsBrightnessCommand(0),
        DesktopActions.windowsBrightnessCommand(70),
      ]);
    },
  );

  test(
    'voice shortcut waits for consent before reaching the host runner',
    () async {
      final runner = _Runner();
      final actions = _actions(runner);
      var consent = false;
      var checks = 0;
      actions.confirmVoiceInputFirstUse = () async {
        checks++;
        return consent;
      };

      await expectLater(actions.voiceInput(), throwsStateError);
      expect(runner.calls, isEmpty);
      consent = true;
      await actions.voiceInput();
      expect(checks, 2);
      expect(runner.calls.single.executable, 'powershell.exe');
      expect(runner.calls.single.arguments.last, "'^+d'");
    },
  );

  test(
    'Vibe deletion requires its matching app and stops after failed selection',
    () async {
      final runner = _Runner(
        results: {0: ProcessResult(1, 9, '', 'Selection denied')},
      );
      final actions = _actions(runner);
      final manifest = DesktopManifest.regularStarter();
      const button = RemoteShortcutButton(
        id: 'vibe.cursor.deleteToStart',
        name: 'Fixture deletion',
        icon: 'keyboard',
        targetType: RemoteTargetType.system,
        target: 'deleteToStart',
      );

      await expectLater(
        actions.executeButton(button, manifest, expectedAppId: 'chatgpt'),
        throwsStateError,
      );
      expect(runner.calls, isEmpty);
      await expectLater(
        actions.executeButton(button, manifest, expectedAppId: 'cursor'),
        throwsA(isA<ProcessException>()),
      );
      expect(runner.calls.single.arguments.sublist(4), [
        "'cursor'",
        "'+{HOME}'",
      ]);

      await actions.executeButton(button, manifest, expectedAppId: 'cursor');
      expect(runner.calls.skip(1).map((call) => call.arguments.sublist(4)), [
        ["'cursor'", "'+{HOME}'"],
        ["'cursor'", "'{BACKSPACE}'"],
      ]);
    },
  );

  test(
    'URL actions reject other schemes and pass each HTTP URL as one argument',
    () async {
      for (final (platform, executable, prefix)
          in <(TargetPlatform, String, List<String>)>[
            (
              TargetPlatform.windows,
              'rundll32.exe',
              ['url.dll,FileProtocolHandler'],
            ),
            (TargetPlatform.macOS, '/usr/bin/open', []),
            (TargetPlatform.linux, 'xdg-open', []),
          ]) {
        final runner = _Runner();
        final actions = _actions(runner, platform);
        for (final invalid in [
          'file:///fixture.txt',
          'mailto:fixture@example.invalid',
          'https:///missing-host',
        ]) {
          await expectLater(actions.openUrl(invalid), throwsFormatException);
        }
        expect(runner.calls, isEmpty);
        const url = 'https://fixture.invalid/help?first=1&second=2';
        await actions.openUrl(url);
        expect(runner.calls.single.executable, executable);
        expect(runner.calls.single.arguments, [...prefix, url]);
      }
    },
  );

  test(
    'disabled buttons and reserved target types never execute commands',
    () async {
      final runner = _Runner();
      final actions = _actions(runner);
      final manifest = DesktopManifest.regularStarter();
      const disabled = RemoteShortcutButton(
        id: 'fixture.disabled',
        name: 'Fixture disabled',
        icon: 'keyboard',
        targetType: RemoteTargetType.keyboardShortcut,
        shortcut: ['CTRL', 'N'],
        enabled: false,
      );
      await expectLater(
        actions.executeButton(disabled, manifest),
        throwsStateError,
      );
      for (final type in [RemoteTargetType.macro, RemoteTargetType.script]) {
        final button = disabled.copyWith(enabled: true, targetType: type);
        await expectLater(
          actions.executeButton(button, manifest),
          throwsUnsupportedError,
        );
      }
      expect(runner.calls, isEmpty);
    },
  );
}
