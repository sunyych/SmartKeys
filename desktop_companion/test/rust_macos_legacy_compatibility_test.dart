import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _LegacyRunner implements DesktopProcessRunner {
  final calls = <({String executable, List<String> arguments})>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: List.of(arguments)));
    return ProcessResult(1, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) async =>
      throw StateError('This test cannot start a host application');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const legacyPointer = MethodChannel('lumiakeys/pointer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const inputs = [
    PointerInput.move(-3, 9),
    PointerInput.button(secondary: true),
    PointerInput.scroll(-4),
  ];

  test('Mac defaults retain the ordered Swift pointer request shape', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(legacyPointer, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(legacyPointer, null));
    final actions = DesktopActions(
      platformOverride: TargetPlatform.macOS,
      environment: const {},
      runner: _LegacyRunner(),
    );

    expect(await actions.probePointerSupport(), isTrue);
    await actions.applyPointerInputs(inputs);

    expect(calls.single.method, 'apply');
    expect(calls.single.arguments, {
      'inputs': inputs.map((input) => input.toJson()).toList(),
    });
  });

  test(
    'Mac default pointer permission errors remain visible to callers',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(legacyPointer, (_) async {
        calls++;
        throw PlatformException(code: 'pointer_permission_missing');
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(legacyPointer, null),
      );
      final actions = DesktopActions(
        platformOverride: TargetPlatform.macOS,
        environment: const {},
        runner: _LegacyRunner(),
      );

      await expectLater(
        actions.applyPointerInputs(inputs),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'pointer_permission_missing',
          ),
        ),
      );
      expect(calls, 1);
    },
  );

  test(
    'Mac default browser shortcut retains Command and target checking',
    () async {
      final runner = _LegacyRunner();
      final actions = DesktopActions(
        platformOverride: TargetPlatform.macOS,
        environment: const {},
        runner: runner,
      );

      await actions.sendShortcut(const [
        'BROWSER_BACK',
      ], expectedAppId: 'safari');

      final call = runner.calls.single;
      expect(call.executable, '/usr/bin/osascript');
      expect(call.arguments.first, '-e');
      final script = call.arguments.last;
      expect(script, contains('if frontName is not "Safari"'));
      expect(script, contains('keystroke "[" using {command down}'));
      expect(
        script.indexOf('if frontName'),
        lessThan(script.indexOf('keystroke')),
      );
    },
  );
}
