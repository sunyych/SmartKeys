import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/windows_desktop_backend.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _RecordingDesktopBackend extends Fake implements WindowsDesktopBackend {
  _RecordingDesktopBackend({this.failure});

  final Object? failure;
  int probes = 0;
  final batches = <List<PointerInput>>[];

  @override
  Future<bool> supportsPointer() async {
    probes++;
    return true;
  }

  @override
  Future<void> applyPointerInputs(List<PointerInput> inputs) async {
    batches.add(List.of(inputs));
    if (failure case final error?) throw error;
  }
}

class _RecordingPointerOverride implements DesktopPointerInput {
  final batches = <List<PointerInput>>[];

  @override
  Future<void> apply(List<PointerInput> inputs) async {
    batches.add(List.of(inputs));
  }
}

const _inputs = [
  PointerInput.move(-3, 9),
  PointerInput.button(secondary: true),
  PointerInput.scroll(-4),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const legacy = MethodChannel('lumiakeys/pointer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> legacyCalls;

  setUp(() {
    legacyCalls = [];
    messenger.setMockMethodCallHandler(legacy, (call) async {
      legacyCalls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(legacy, null));

  test(
    'Windows pointer probe and ordered batch reach the Rust backend',
    () async {
      final native = _RecordingDesktopBackend();
      final actions = DesktopActions(
        platformOverride: TargetPlatform.windows,
        windowsDesktopBackend: native,
      );

      expect(await actions.probePointerSupport(), isTrue);
      await actions.applyPointerInputs(_inputs);

      expect(native.probes, 1);
      expect(native.batches, [_inputs]);
      expect(legacyCalls, isEmpty);
    },
  );

  test(
    'native partial pointer failure propagates without a legacy replay',
    () async {
      final error = StateError('Synthetic partial pointer delivery');
      final native = _RecordingDesktopBackend(failure: error);
      final actions = DesktopActions(
        platformOverride: TargetPlatform.windows,
        windowsDesktopBackend: native,
      );

      await expectLater(
        actions.applyPointerInputs(_inputs),
        throwsA(same(error)),
      );
      expect(native.batches, [_inputs]);
      expect(legacyCalls, isEmpty);
    },
  );

  test(
    'explicit pointer adapter keeps precedence over the Rust backend',
    () async {
      final native = _RecordingDesktopBackend();
      final pointer = _RecordingPointerOverride();
      final actions = DesktopActions(
        platformOverride: TargetPlatform.windows,
        pointerInput: pointer,
        windowsDesktopBackend: native,
      );

      expect(await actions.probePointerSupport(), isTrue);
      await actions.applyPointerInputs(_inputs);
      expect(pointer.batches, [_inputs]);
      expect(native.probes, 0);
      expect(native.batches, isEmpty);
      expect(legacyCalls, isEmpty);
    },
  );
}
