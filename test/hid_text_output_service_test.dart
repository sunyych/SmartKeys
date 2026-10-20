import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/hid_text_output_service.dart';

void main() {
  test('maps every printable ASCII character and rejects non-text output', () {
    final allPrintable = String.fromCharCodes(
      List.generate(0x7f - 0x20, (index) => 0x20 + index),
    );
    final strokes = UsAsciiHidTextEncoder.encode(allPrintable);
    expect(strokes, hasLength(95));

    HidTextStroke expected(int code) {
      if (code >= 0x61 && code <= 0x7a) {
        return HidTextStroke(usage: 0x04 + code - 0x61, shift: false);
      }
      if (code >= 0x41 && code <= 0x5a) {
        return HidTextStroke(usage: 0x04 + code - 0x41, shift: true);
      }
      if (code >= 0x31 && code <= 0x39) {
        return HidTextStroke(usage: 0x1e + code - 0x31, shift: false);
      }
      if (code == 0x30) return const HidTextStroke(usage: 0x27, shift: false);
      const punctuation = <int, HidTextStroke>{
        0x20: HidTextStroke(usage: 0x2c, shift: false),
        0x21: HidTextStroke(usage: 0x1e, shift: true),
        0x22: HidTextStroke(usage: 0x34, shift: true),
        0x23: HidTextStroke(usage: 0x20, shift: true),
        0x24: HidTextStroke(usage: 0x21, shift: true),
        0x25: HidTextStroke(usage: 0x22, shift: true),
        0x26: HidTextStroke(usage: 0x24, shift: true),
        0x27: HidTextStroke(usage: 0x34, shift: false),
        0x28: HidTextStroke(usage: 0x26, shift: true),
        0x29: HidTextStroke(usage: 0x27, shift: true),
        0x2a: HidTextStroke(usage: 0x25, shift: true),
        0x2b: HidTextStroke(usage: 0x2e, shift: true),
        0x2c: HidTextStroke(usage: 0x36, shift: false),
        0x2d: HidTextStroke(usage: 0x2d, shift: false),
        0x2e: HidTextStroke(usage: 0x37, shift: false),
        0x2f: HidTextStroke(usage: 0x38, shift: false),
        0x3a: HidTextStroke(usage: 0x33, shift: true),
        0x3b: HidTextStroke(usage: 0x33, shift: false),
        0x3c: HidTextStroke(usage: 0x36, shift: true),
        0x3d: HidTextStroke(usage: 0x2e, shift: false),
        0x3e: HidTextStroke(usage: 0x37, shift: true),
        0x3f: HidTextStroke(usage: 0x38, shift: true),
        0x40: HidTextStroke(usage: 0x1f, shift: true),
        0x5b: HidTextStroke(usage: 0x2f, shift: false),
        0x5c: HidTextStroke(usage: 0x31, shift: false),
        0x5d: HidTextStroke(usage: 0x30, shift: false),
        0x5e: HidTextStroke(usage: 0x23, shift: true),
        0x5f: HidTextStroke(usage: 0x2d, shift: true),
        0x60: HidTextStroke(usage: 0x35, shift: false),
        0x7b: HidTextStroke(usage: 0x2f, shift: true),
        0x7c: HidTextStroke(usage: 0x31, shift: true),
        0x7d: HidTextStroke(usage: 0x30, shift: true),
        0x7e: HidTextStroke(usage: 0x35, shift: true),
      };
      return punctuation[code]!;
    }

    for (var index = 0; index < strokes.length; index++) {
      expect(strokes[index], expected(0x20 + index));
    }
    for (final unsupported in ['\n', '\t', '\u007f', 'é', '汉', '🎤']) {
      expect(
        () => UsAsciiHidTextEncoder.encode('prefix$unsupported'),
        throwsA(isA<HidTextOutputException>()),
      );
    }
    expect(
      () => UsAsciiHidTextEncoder.encode('x' * 257),
      throwsA(isA<HidTextOutputException>()),
    );
  });

  test('maps printable ASCII to deterministic US keyboard usages', () {
    final strokes = UsAsciiHidTextEncoder.encode('Az09 !@');
    expect(strokes, const [
      HidTextStroke(usage: 0x04, shift: true),
      HidTextStroke(usage: 0x1d, shift: false),
      HidTextStroke(usage: 0x27, shift: false),
      HidTextStroke(usage: 0x26, shift: false),
      HidTextStroke(usage: 0x2c, shift: false),
      HidTextStroke(usage: 0x1e, shift: true),
      HidTextStroke(usage: 0x1f, shift: true),
    ]);
    expect(UsAsciiHidTextEncoder.encode(''), isEmpty);
  });

  test(
    'legacy Windows profile is rejected before a session or native output',
    () {
      final hid = RecordingHidService();
      final output = HidTextOutputService(hid: hid);

      expect(
        () => output.beginSession(profile: HidTextProfile.windowsHexNumpad),
        throwsA(isA<HidTextOutputException>()),
      );
      expect(output.pendingPhraseCount, 0);
      expect(hid.textBatches, isEmpty);
      expect(hid.cancelledTextBatches, isEmpty);
      output.dispose();
      hid.dispose();
    },
  );

  test('rejects an unsupported character before queueing any output', () async {
    final hid = RecordingHidService();
    final output = HidTextOutputService(hid: hid);
    final session = output.beginSession();

    expect(
      () => output.sendText(session, 'valid prefix 汉'),
      throwsA(isA<HidTextOutputException>()),
    );
    expect(hid.textBatches, isEmpty);
    expect(hid.cancelledTextBatches, isEmpty);
    await output.cancelSession(session);
    hid.dispose();
  });

  test(
    'serializes phrases and pins every batch to the captured host',
    () async {
      final hid = RecordingHidService();
      final gates = <Completer<void>>[];
      var active = 0;
      var maxActive = 0;
      hid.onTextBatch = () async {
        final gate = Completer<void>();
        gates.add(gate);
        active++;
        if (active > maxActive) maxActive = active;
        await gate.future;
        active--;
      };
      final output = HidTextOutputService(hid: hid);
      final session = output.beginSession();
      final first = output.sendText(session, 'one');
      final second = output.sendText(session, 'two');

      await Future<void>.delayed(Duration.zero);
      expect(hid.textBatches, hasLength(1));
      expect(hid.textBatches.single.expectedAddress, '00:11:22:33:44:55');
      gates.single.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(hid.textBatches, hasLength(2));
      expect(hid.textBatches.last.expectedAddress, '00:11:22:33:44:55');
      gates.last.complete();
      await second;
      expect(maxActive, 1);
      await output.cancelSession(session);
      hid.dispose();
    },
  );

  test('reports a failed Bluetooth batch without retrying it', () async {
    final hid = RecordingHidService()..textBatchError = StateError('rejected');
    final output = HidTextOutputService(hid: hid);
    final session = output.beginSession();

    await expectLater(output.sendText(session, 'hello'), throwsStateError);
    expect(hid.textBatches, hasLength(1));
    await output.cancelSession(session);
    output.dispose();
    hid.dispose();
  });

  test(
    'a partial output failure cancels every queued phrase and session',
    () async {
      final hid = RecordingHidService()
        ..textBatchError = StateError('rejected');
      final output = HidTextOutputService(hid: hid);
      final session = output.beginSession();
      final first = output.sendText(session, 'first');
      final queued = output.sendText(session, 'queued');

      await expectLater(first, throwsStateError);
      await expectLater(queued, throwsA(isA<HidTextOutputException>()));
      expect(hid.textBatches, hasLength(1));
      expect(
        () => output.sendText(session, 'must not continue'),
        throwsA(isA<HidTextOutputException>()),
      );
      output.dispose();
      hid.dispose();
    },
  );

  test(
    'a host A to B to A transition invalidates the captured session',
    () async {
      final hid = RecordingHidService();
      final output = HidTextOutputService(hid: hid);
      final session = output.beginSession();
      hid.selectedHost.value = const HidHost(
        id: 'host-b',
        name: 'Second Computer',
        address: '11:22:33:44:55:66',
      );
      hid.selectedHost.value = const HidHost(
        id: 'host-a',
        name: 'Test Computer',
        address: '00:11:22:33:44:55',
      );

      expect(
        () => output.sendText(session, 'no replay'),
        throwsA(isA<HidTextOutputException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(hid.textBatches, isEmpty);
      expect(hid.cancelledTextBatches, hasLength(1));
      output.dispose();
      hid.dispose();
    },
  );

  test(
    'late cleanup from one panel cannot release another panel output',
    () async {
      final hid = RecordingHidService();
      final cancelEntered = Completer<void>();
      final finishCancel = Completer<void>();
      var cancelCalls = 0;
      hid.onCancelTextBatch = (_) async {
        cancelCalls++;
        if (cancelCalls == 1) {
          cancelEntered.complete();
          await finishCancel.future;
        }
      };
      final oldPanel = HidTextOutputService(hid: hid);
      final oldSession = oldPanel.beginSession();
      final cancelling = oldPanel.cancelSession(oldSession);
      await cancelEntered.future;

      final newPanel = HidTextOutputService(hid: hid);
      final newSession = newPanel.beginSession();
      await newPanel.sendText(newSession, 'new panel');
      finishCancel.complete();
      await cancelling;

      expect(hid.textBatches, hasLength(1));
      expect(hid.textBatches.single.sessionToken, newSession.token);
      expect(oldSession.token, isNot(newSession.token));
      expect(hid.calls, isNot(contains('releaseAllKeys')));
      await newPanel.cancelSession(newSession);
      oldPanel.dispose();
      newPanel.dispose();
      hid.dispose();
    },
  );
}
