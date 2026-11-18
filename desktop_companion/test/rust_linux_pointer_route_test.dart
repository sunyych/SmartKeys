import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_native_backend.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _NativePointer extends Fake implements NativeDesktopBackend {
  _NativePointer({this.ready = true, this.failure});

  final bool ready;
  final StateError? failure;
  int probes = 0;
  final batches = <List<Map<String, Object?>>>[];

  @override
  Future<bool> supportsPointer() async {
    probes++;
    return ready;
  }

  @override
  Future<void> applyPointerInputs(List<PointerInput> inputs) async {
    batches.add(inputs.map((input) => input.toJson()).toList());
    if (failure case final error?) throw error;
  }
}

class _PointerOverride implements DesktopPointerInput {
  final batches = <List<PointerInput>>[];

  @override
  Future<void> apply(List<PointerInput> inputs) async {
    batches.add(List.of(inputs));
  }
}

class _LegacyRunner implements DesktopProcessRunner {
  final calls = <({String command, List<String> args})>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((command: executable, args: List.of(arguments)));
    return ProcessResult(1, 0, 'X=20\nY=-30\n', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) async =>
      throw StateError('Unexpected detached process');
}

const _x11 = {'DISPLAY': ':99'};
const _batch = [
  PointerInput.move(-127, 127),
  PointerInput.scroll(-2),
  PointerInput.button(secondary: true),
  PointerInput.scroll(3),
  PointerInput.button(secondary: false),
];

void main() {
  test('Linux Rust backend requires the portable opt-in flag', () {
    expect(
      selectNativeDesktopBackend(
        platform: TargetPlatform.linux,
        environment: {..._x11, 'LUMIAKEY_WINDOWS_DESKTOP_BACKEND': 'rust'},
      ),
      isNull,
    );
    expect(
      selectNativeDesktopBackend(
        platform: TargetPlatform.linux,
        environment: {..._x11, 'LUMIAKEY_DESKTOP_BACKEND': 'rust'},
      ),
      isA<RustDesktopBackend>(),
    );
  });

  test(
    'opt-in Linux X11 forwards the complete ordered batch to Rust',
    () async {
      final runner = _LegacyRunner();
      final native = _NativePointer();
      final actions = DesktopActions(
        platformOverride: TargetPlatform.linux,
        environment: _x11,
        desktopBackend: native,
        runner: runner,
      );

      expect(await actions.probePointerSupport(), isTrue);
      await actions.applyPointerInputs(_batch);

      expect(native.probes, 1);
      expect(native.batches, [
        [
          {'kind': 'move', 'x': -127, 'y': 127},
          {'kind': 'scroll', 'y': -2},
          {'kind': 'button', 'secondary': true},
          {'kind': 'scroll', 'y': 3},
          {'kind': 'button', 'secondary': false},
        ],
      ]);
      expect(runner.calls, isEmpty);
    },
  );

  test(
    'unavailable Rust X11 support does not advertise legacy readiness',
    () async {
      final runner = _LegacyRunner();
      final native = _NativePointer(ready: false);
      final actions = DesktopActions(
        platformOverride: TargetPlatform.linux,
        environment: _x11,
        desktopBackend: native,
        runner: runner,
      );

      expect(await actions.probePointerSupport(), isFalse);
      expect(native.probes, 1);
      expect(native.batches, isEmpty);
      expect(runner.calls, isEmpty);
    },
  );

  test(
    'native partial pointer failure is never replayed via xdotool',
    () async {
      final runner = _LegacyRunner();
      final failure = StateError('Synthetic partial batch');
      final native = _NativePointer(failure: failure);
      final actions = DesktopActions(
        platformOverride: TargetPlatform.linux,
        environment: _x11,
        desktopBackend: native,
        runner: runner,
      );

      await expectLater(
        Future<void>.sync(() => actions.applyPointerInputs(_batch)),
        throwsA(same(failure)),
      );
      expect(native.batches, hasLength(1));
      expect(runner.calls, isEmpty);
    },
  );

  for (final (session, environment) in [
    (
      'Wayland also exposing DISPLAY',
      {..._x11, 'WAYLAND_DISPLAY': 'wayland-0'},
    ),
    ('Wayland reported by XDG', {..._x11, 'XDG_SESSION_TYPE': 'WaYlAnD'}),
    ('headless Linux', <String, String>{}),
  ]) {
    test(
      '$session blocks pointer and keyboard routes before probing',
      () async {
        final runner = _LegacyRunner();
        final native = _NativePointer();
        final actions = DesktopActions(
          platformOverride: TargetPlatform.linux,
          environment: environment,
          desktopBackend: native,
          runner: runner,
        );

        expect(await actions.probePointerSupport(), isFalse);
        await expectLater(
          Future<void>.sync(() => actions.applyPointerInputs(_batch)),
          throwsUnsupportedError,
        );
        await expectLater(
          actions.sendShortcut(['CTRL', 'C']),
          throwsUnsupportedError,
        );
        expect(native.probes, 0);
        expect(native.batches, isEmpty);
        expect(runner.calls, isEmpty);
      },
    );
  }

  test(
    'injected pointer adapter keeps precedence over opted-in Rust',
    () async {
      final runner = _LegacyRunner();
      final native = _NativePointer();
      final adapter = _PointerOverride();
      final actions = DesktopActions(
        platformOverride: TargetPlatform.linux,
        environment: _x11,
        desktopBackend: native,
        pointerInput: adapter,
        runner: runner,
      );

      expect(await actions.probePointerSupport(), isTrue);
      await actions.applyPointerInputs(_batch);
      expect(adapter.batches, [_batch]);
      expect(native.probes, 0);
      expect(native.batches, isEmpty);
      expect(runner.calls, isEmpty);
    },
  );

  test('the default X11 backend continues to use legacy xdotool', () async {
    final runner = _LegacyRunner();
    final actions = DesktopActions(
      platformOverride: TargetPlatform.linux,
      environment: _x11,
      runner: runner,
    );

    expect(await actions.probePointerSupport(), isTrue);
    await actions.applyPointerInputs([
      const PointerInput.button(secondary: true),
    ]);
    expect(runner.calls.map((call) => [call.command, ...call.args]), [
      ['xdotool', 'getmouselocation', '--shell'],
      ['xdotool', 'click', '3'],
    ]);
  });
}
