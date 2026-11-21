import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dictationChannel = MethodChannel('test/lumiakeys/dictation');
  const macInputChannel = MethodChannel('test/lumiakeys/mac_input');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final button = RemoteShortcutButton(
    id: chatGptSystemDictationShortcutId,
    name: 'Dictate',
    icon: 'mic_external_on',
    targetType: RemoteTargetType.system,
    target: chatGptSystemDictationTarget,
  );

  tearDown(() {
    messenger.setMockMethodCallHandler(dictationChannel, null);
    messenger.setMockMethodCallHandler(macInputChannel, null);
  });

  test(
    'runs native system Dictation only for the managed ChatGPT target',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(dictationChannel, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(
        macInputChannel,
        (call) async => false,
      );
      final actions = DesktopActions(
        platformOverride: TargetPlatform.macOS,
        dictationChannel: dictationChannel,
        macInputChannel: macInputChannel,
      );

      await actions.executeButton(
        button,
        DesktopManifest.regularStarter(),
        expectedAppId: 'chatgpt',
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'startSystemDictation');
    },
  );

  test(
    'rejects a different managed target before invoking native Dictation',
    () async {
      var invoked = false;
      messenger.setMockMethodCallHandler(dictationChannel, (call) async {
        invoked = true;
        return null;
      });
      messenger.setMockMethodCallHandler(
        macInputChannel,
        (call) async => false,
      );
      final actions = DesktopActions(
        platformOverride: TargetPlatform.macOS,
        dictationChannel: dictationChannel,
        macInputChannel: macInputChannel,
      );

      await expectLater(
        actions.executeButton(
          button,
          DesktopManifest.regularStarter(),
          expectedAppId: 'cursor',
        ),
        throwsUnsupportedError,
      );
      expect(invoked, isFalse);
    },
  );

  test(
    'rejects Dictate on a host that cannot invoke macOS system Dictation',
    () async {
      var invoked = false;
      messenger.setMockMethodCallHandler(dictationChannel, (call) async {
        invoked = true;
        return null;
      });
      final actions = DesktopActions(
        platformOverride: TargetPlatform.windows,
        dictationChannel: dictationChannel,
      );

      await expectLater(
        actions.executeButton(
          button,
          DesktopManifest.regularStarter(),
          expectedAppId: 'chatgpt',
        ),
        throwsUnsupportedError,
      );
      expect(invoked, isFalse);
    },
  );

  test(
    'does not expose the action when the native shortcut route is disabled',
    () async {
      var invoked = false;
      messenger.setMockMethodCallHandler(dictationChannel, (call) async {
        invoked = true;
        return null;
      });
      messenger.setMockMethodCallHandler(macInputChannel, (call) async => true);
      final actions = DesktopActions(
        platformOverride: TargetPlatform.macOS,
        dictationChannel: dictationChannel,
        macInputChannel: macInputChannel,
      );
      await actions.readMacInputMode();

      expect(actions.supportsSystemDictation, isFalse);
      await expectLater(
        actions.executeButton(
          button,
          DesktopManifest.regularStarter(),
          expectedAppId: 'chatgpt',
        ),
        throwsUnsupportedError,
      );
      expect(invoked, isFalse);
    },
  );
}
