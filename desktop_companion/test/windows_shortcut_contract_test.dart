import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';

class _RecordingProcessRunner implements DesktopProcessRunner {
  _RecordingProcessRunner({this.exitCode = 0, this.failure});

  final int exitCode;
  final Exception? failure;
  final calls = <({String executable, List<String> arguments})>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: arguments));
    if (failure case final failure?) throw failure;
    return ProcessResult(
      1,
      exitCode,
      '',
      exitCode == 0 ? '' : 'Windows shortcut delivery failed',
    );
  }

  @override
  Future<Process> start(String executable, List<String> arguments) {
    throw StateError('A shortcut must not launch a detached process');
  }
}

DesktopActions _windowsActions(_RecordingProcessRunner runner) =>
    DesktopActions(
      platformOverride: TargetPlatform.windows,
      runner: runner,
      environment: const {},
    );

void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/windows_shortcuts.json').readAsStringSync(),
          )
          as Map<String, Object?>;

  for (final shortcut
      in (fixture['accepted'] as List).cast<Map<String, Object?>>()) {
    test('legacy backend accepts ${shortcut['id']}', () async {
      final runner = _RecordingProcessRunner();
      final processes = (shortcut['allowedProcesses'] as List? ?? [])
          .cast<String>();

      await _windowsActions(runner).sendShortcut(
        (shortcut['keys'] as List).cast<String>(),
        expectedAppId: shortcut['target'] as String?,
      );

      final call = runner.calls.single;
      expect(call.executable, 'powershell.exe');
      expect(call.arguments.sublist(0, 3), [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
      ]);
      expect(call.arguments.sublist(4), [
        "'${processes.join(',')}'",
        "'${shortcut['legacyStroke']}'",
      ]);

      final script = call.arguments[3];
      expect(script, contains(r'param($approvedProcesses, $keyStroke)'));
      final send = script.indexOf(r'::SendWait($keyStroke)');
      expect(send, greaterThanOrEqualTo(0));
      if (processes.isNotEmpty) {
        expect(
          script.substring(0, send),
          contains(r'$foregroundHandle = [LK]::GetForegroundWindow()'),
        );
        expect(
          script.substring(0, send),
          contains(r'-notcontains $p.ProcessName.ToLowerInvariant()'),
        );
      }
      if (shortcut['requireMainWindow'] == true) {
        final guard = script.substring(0, send);
        expect(guard, contains(r"-contains 'chatgpt'"));
        expect(
          guard,
          contains(r'-not [LK]::IsWindowVisible($foregroundHandle)'),
        );
        expect(guard, contains(r'$style -band 0x80'));
        expect(guard, contains(r'$style -band 0x08000000'));
        expect(
          guard,
          contains(r'[LK]::GetWindow($foregroundHandle, 4) -ne [IntPtr]::Zero'),
        );
      }
    });
  }

  for (final shortcut
      in (fixture['rejected'] as List).cast<Map<String, Object?>>()) {
    test('rejects ${shortcut['id']} before delivery', () async {
      final runner = _RecordingProcessRunner();

      await expectLater(
        _windowsActions(
          runner,
        ).sendShortcut((shortcut['keys'] as List).cast<String>()),
        throwsFormatException,
      );

      expect(runner.calls, isEmpty);
    });
  }

  test(
    'delivery failure reports process exit status and does not retry',
    () async {
      final runner = _RecordingProcessRunner(exitCode: 9);

      await expectLater(
        _windowsActions(runner).sendShortcut(const ['CTRL', 'A']),
        throwsA(
          isA<ProcessException>()
              .having((error) => error.errorCode, 'exit code', 9)
              .having(
                (error) => error.message,
                'message',
                'Windows shortcut delivery failed',
              ),
        ),
      );

      expect(runner.calls, hasLength(1));
    },
  );

  test('process start failure is propagated without retry', () async {
    final failure = const ProcessException(
      'powershell.exe',
      [],
      'start failed',
    );
    final runner = _RecordingProcessRunner(failure: failure);

    await expectLater(
      _windowsActions(runner).sendShortcut(const ['CTRL', 'A']),
      throwsA(same(failure)),
    );

    expect(runner.calls, hasLength(1));
  });
}
