import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('starter manifest round trips and keeps globally unique buttons', () {
    final original = DesktopManifest.starter();
    final restored = DesktopManifest.fromJson(original.toJson());

    expect(restored.currentProfileId, 'default');
    expect(restored.layoutById('codex')!.buttons, hasLength(15));
    expect(restored.buttonById('codex.open')!.target, 'codex');
    expect(
      restored.buttonById('codex.voice')!.targetType,
      RemoteTargetType.voiceInput,
    );
    expect(restored.buttonById('codex.send')!.shortcut, ['ENTER']);
    expect(restored.layoutById('codex')!.buttons.map((button) => button.id), [
      'codex.open',
      'codex.voice',
      'codex.newChat',
      'codex.previousConversation',
      'codex.nextConversation',
      'codex.send',
      'codex.searchChats',
      'codex.findInChat',
      'codex.openFolder',
      'codex.commandMenu',
      'codex.terminal',
      'codex.review',
      'codex.back',
      'codex.forward',
      'codex.sidebar',
    ]);
    expect(restored.applicationById('vscode')!.layoutId, 'app.vscode');
    expect(restored.profiles.map((profile) => profile.id), ['default']);
  });

  test(
    'sync settings omit apps and icons without changing desktop storage',
    () {
      final original = DesktopManifest.starter();
      final restricted = original.copyWith(
        settings: original.settings.copyWith(
          enableAppsSync: false,
          syncIcons: false,
        ),
      );

      final synced = DesktopManifest.fromJson(restricted.toJson(forSync: true));
      expect(synced.applications, isEmpty);
      expect(synced.layouts.first.buttons.first.icon, isEmpty);
      expect(restricted.applications, isNotEmpty);
    },
  );

  test('phone sync only includes applications detected on the Desktop', () {
    final original = DesktopManifest.starter();
    final detected = original.copyWith(
      applications: original.applications
          .map(
            (application) => application.copyWith(
              detected: application.id == 'codex',
              running: application.id == 'codex',
            ),
          )
          .toList(growable: false),
    );

    final synced = DesktopManifest.fromJson(detected.toJson(forSync: true));
    expect(synced.applications.single.id, 'codex');
    expect(synced.applications.single.running, isTrue);
  });

  test('remote actions only contain desktop-owned identifiers', () {
    expect(
      RemoteActionRequest.button('keyboard.copy').toJson(),
      containsPair('buttonId', 'keyboard.copy'),
    );
    expect(
      RemoteActionRequest.launchApplication('vscode').toJson(),
      containsPair('applicationId', 'vscode'),
    );
  });
}
