import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_native_backend.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _NoProcess extends Fake implements DesktopProcessRunner {}

class _RecordingNativeDesktop extends Fake implements NativeDesktopBackend {
  _RecordingNativeDesktop({this.pointerAvailable = true, this.failure});

  final bool pointerAvailable;
  Object? failure;
  Object? foregroundFailure;
  int probes = 0;
  int foregroundReads = 0;
  final batches = <List<PointerInput>>[];

  @override
  Future<bool> supportsPointer() async {
    probes++;
    return pointerAvailable;
  }

  @override
  Future<void> applyPointerInputs(List<PointerInput> inputs) async {
    batches.add(List.of(inputs));
    if (failure case final error?) throw error;
  }

  @override
  Future<String?> readForegroundProcess() async {
    foregroundReads++;
    if (foregroundFailure case final error?) throw error;
    return null;
  }
}

class _ExplicitPointer implements DesktopPointerInput {
  final batches = <List<PointerInput>>[];

  @override
  Future<void> apply(List<PointerInput> inputs) async {
    batches.add(List.of(inputs));
  }
}

const _mixedInputs = [
  PointerInput.move(-127, 127),
  PointerInput.button(secondary: true),
  PointerInput.scroll(-6),
  PointerInput.button(secondary: false),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const swiftPointer = MethodChannel('lumiakeys/pointer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> swiftCalls;

  setUp(() {
    swiftCalls = [];
    messenger.setMockMethodCallHandler(swiftPointer, (call) async {
      swiftCalls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(swiftPointer, null));

  DesktopActions macActions(
    _RecordingNativeDesktop backend, {
    DesktopPointerInput? pointer,
  }) => DesktopActions(
    platformOverride: TargetPlatform.macOS,
    environment: const {},
    desktopBackend: backend,
    pointerInput: pointer,
    runner: _NoProcess(),
  );

  test('Mac Rust route passes a mixed pointer batch in caller order', () async {
    final native = _RecordingNativeDesktop();
    final actions = macActions(native);

    expect(await actions.probePointerSupport(), isTrue);
    await actions.applyPointerInputs(_mixedInputs);

    expect(native.probes, 1);
    expect(
      native.batches.single.map((input) => input.toJson()),
      _mixedInputs.map((input) => input.toJson()),
    );
    expect(swiftCalls, isEmpty);
  });

  test(
    'Mac Rust keeps pointer capability available while permission is denied',
    () async {
      final permissionError = StateError('Synthetic event permission denied');
      final native = _RecordingNativeDesktop(failure: permissionError);
      final actions = macActions(native);

      expect(await actions.probePointerSupport(), isTrue);
      await expectLater(
        actions.applyPointerInputs(_mixedInputs),
        throwsA(same(permissionError)),
      );
      expect(native.probes, 1);
      expect(native.batches, [_mixedInputs]);
      expect(swiftCalls, isEmpty);

      native.failure = null;
      const next = [PointerInput.move(2, 3)];
      await actions.applyPointerInputs(next);
      expect(native.batches, [_mixedInputs, next]);
      expect(native.probes, 1);
      expect(swiftCalls, isEmpty);
    },
  );

  test('Mac Rust partial input failure is returned without a replay', () async {
    final error = StateError('Synthetic partial delivery');
    final native = _RecordingNativeDesktop(failure: error);
    final actions = macActions(native);

    await expectLater(
      actions.applyPointerInputs(_mixedInputs),
      throwsA(same(error)),
    );
    expect(native.batches, [_mixedInputs]);
    expect(swiftCalls, isEmpty);
  });

  test('an explicit Mac pointer adapter takes precedence over Rust', () async {
    final native = _RecordingNativeDesktop(pointerAvailable: false);
    final override = _ExplicitPointer();
    final actions = macActions(native, pointer: override);

    expect(await actions.probePointerSupport(), isTrue);
    await actions.applyPointerInputs(_mixedInputs);

    expect(override.batches, [_mixedInputs]);
    expect(native.probes, 0);
    expect(native.batches, isEmpty);
    expect(swiftCalls, isEmpty);
  });

  test(
    'Mac keeps an empty Rust foreground result and falls back on read failure',
    () async {
      final native = _RecordingNativeDesktop();
      final reads = <({String executable, List<String> arguments})>[];
      final discovery = PlatformApplicationDiscovery(
        desktopBackend: native,
        runProcess: (executable, arguments) async {
          reads.add((executable: executable, arguments: List.of(arguments)));
          return ProcessResult(1, 0, 'ChatGPT\n', '');
        },
      );
      const chatGpt = RemoteApplication(
        id: 'chatgpt',
        name: 'ChatGPT',
        icon: 'apps',
        executable: 'ChatGPT',
        layoutId: 'chatgpt',
      );

      expect(await discovery.isForeground(chatGpt), isFalse);
      expect(native.foregroundReads, 1);
      expect(reads, isEmpty);

      native.foregroundFailure = StateError('Synthetic native read failure');
      expect(await discovery.isForeground(chatGpt), isTrue);
      expect(native.foregroundReads, 2);
      expect(reads.single.executable, '/usr/bin/osascript');
      expect(reads.single.arguments.last, contains('whose frontmost is true'));
      expect(reads.single.arguments.last, isNot(contains('keystroke')));
    },
    skip: !Platform.isMacOS,
  );
}
