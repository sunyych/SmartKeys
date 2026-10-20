import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/dictation_receiver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native input-busy typing requires rejected status and allowlisted reason',
    () async {
      const channel = MethodChannel('lumiakeys/dictation-test');
      final sink = MethodChannelDictationTextSink(channel: channel);
      Object? response;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => response);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      for (final reason in [
        'modifier_key_held',
        'foreground_changed_or_modifier_held',
        'held_modifier',
      ]) {
        response = {'status': 'rejected', 'reason': reason};
        await expectLater(
          sink.insertText('word'),
          throwsA(isA<DictationInputBusyException>()),
        );
      }

      for (final rejected in [
        {'status': 'partial', 'reason': 'modifier_key_held'},
        {'status': 'rejected', 'reason': 'unknown'},
        {'status': 'rejected', 'reason': 'target_or_permission_changed'},
        {'status': 'rejected', 'reason': null},
        null,
      ]) {
        response = rejected;
        await expectLater(sink.insertText('word'), throwsA(isA<StateError>()));
      }

      response = {'status': 'submitted', 'reason': 'modifier_key_held'};
      await sink.insertText('word');
    },
  );
}
