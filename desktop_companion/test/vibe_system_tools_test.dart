import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/vibe_system_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lumiakeys/vibe_system_tools');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forwards only fixed app and action identifiers', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return {'status': 'delivered'};
        });

    await VibeSystemTools(channel: channel).execute('codex', 'quote');

    expect(received?.method, 'execute');
    expect(received?.arguments, {'appId': 'codex', 'actionId': 'quote'});
  });

  test(
    'unified ChatGPT Codex controls preserve fixed system-action routing',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return {'status': 'delivered'};
          });
      final manifest = DesktopManifest.starter();
      final button = manifest.buttonById('chatgpt.codex.quote')!;

      await DesktopActions(
        vibeSystemTools: VibeSystemTools(channel: channel),
      ).executeButton(button, manifest, expectedAppId: 'chatgpt');

      expect(received?.arguments, {'appId': 'codex', 'actionId': 'quote'});
    },
  );

  test('rejects app IDs and action payloads outside the fixed allowlist', () {
    final tools = VibeSystemTools(channel: channel);
    expect(() => tools.execute('other-app', 'comma'), throwsFormatException);
    expect(
      () => tools.execute('codex', 'insert arbitrary text'),
      throwsFormatException,
    );
  });

  test('reports native foreground-app rejection', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return {'status': 'rejected', 'reason': 'wrong_foreground_app'};
        });

    await expectLater(
      VibeSystemTools(channel: channel).execute('claude', 'period'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.message,
          'message',
          'wrong_foreground_app',
        ),
      ),
    );
  });
}
