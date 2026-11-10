import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('starter manifest round trips and keeps globally unique buttons', () {
    final original = DesktopManifest.starter();
    final restored = DesktopManifest.fromJson(original.toJson());

    expect(restored.currentProfileId, 'default');
    expect(restored.layoutById('codex')!.buttons, hasLength(15));
    expect(restored.buttonById('codex.open'), isNull);
    expect(restored.buttonById('codex.focusInput')!.shortcut, ['ESC']);
    expect(
      restored.buttonById('codex.voice')!.targetType,
      RemoteTargetType.voiceInput,
    );
    expect(restored.buttonById('codex.send')!.shortcut, ['ENTER']);
    expect(restored.layoutById('codex')!.buttons.map((button) => button.id), [
      'codex.focusInput',
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
    expect(restored.applicationById('codex')!.name, 'Codex / ChatGPT');
    expect(restored.applicationById('appleMusic')!.executable, 'Music');
    expect(restored.applicationById('finder')!.executable, 'Finder');
    expect(restored.layoutById('app.finder')!.buttons, hasLength(15));
    expect(restored.layoutById('app.chrome')!.buttons, hasLength(15));
    expect(restored.buttonById('chrome.bookmark'), isNotNull);
    expect(restored.buttonById('chrome.pageUp'), isNull);
    expect(restored.buttonById('chrome.pageDown'), isNull);
    expect(restored.buttonById('chrome.nextTab'), isNotNull);
    expect(
      restored.buttonById('chrome.passwordManager')!.target,
      'https://passwords.google.com/',
    );
    expect(restored.buttonById('chrome.playPause')!.shortcut, ['SPACE']);
    expect(restored.buttonById('chrome.stop')!.shortcut, ['ESC']);
    expect(restored.buttonById('chrome.mute')!.shortcut, ['M']);
    expect(restored.profiles.map((profile) => profile.id), ['default']);
  });

  test('starter exposes stable Vibe app layouts and project bindings', () {
    final manifest = DesktopManifest.fromJson(
      DesktopManifest.starter().toJson(),
    );
    for (final app in const ['codex', 'claude', 'cursor']) {
      expect(manifest.layoutById('vibe.$app'), isNotNull);
      expect(manifest.buttonById('vibe.$app.project'), isNotNull);
    }
    expect(manifest.applicationById('codex')!.layoutId, 'codex');
    expect(manifest.buttonById('vibe.codex.project')!.shortcut, [
      'PRIMARY',
      'ALT',
      'SHIFT',
      'O',
    ]);
    expect(manifest.buttonById('vibe.cursor.project')!.enabled, isTrue);
    expect(
      manifest.buttonById('vibe.claude.project')!.description,
      contains('choose its project folder'),
    );
    expect(manifest.buttonById('vibe.codex.previousChat')!.shortcut, [
      'PRIMARY',
      'SHIFT',
      '[',
    ]);
    expect(manifest.buttonById('vibe.codex.nextChat')!.shortcut, [
      'PRIMARY',
      'SHIFT',
      ']',
    ]);
    expect(manifest.buttonById('vibe.codex.terminal')!.shortcut, ['CTRL', '`']);
    expect(manifest.buttonById('vibe.codex.review')!.shortcut, [
      'CTRL',
      'SHIFT',
      'G',
    ]);
    expect(manifest.buttonById('vibe.claude.previousSession')!.shortcut, [
      'CTRL',
      'SHIFT',
      'TAB',
    ]);
    expect(manifest.buttonById('vibe.claude.nextSession')!.shortcut, [
      'CTRL',
      'TAB',
    ]);
    expect(manifest.buttonById('vibe.cursor.previousChat')!.shortcut, [
      'PRIMARY',
      '[',
    ]);
    expect(manifest.buttonById('vibe.cursor.nextChat')!.shortcut, [
      'PRIMARY',
      ']',
    ]);
    expect(manifest.buttonById('vibe.cursor.agentPanel')!.shortcut, [
      'PRIMARY',
      'I',
    ]);
    for (final app in const ['codex', 'claude', 'cursor']) {
      for (final action in const [
        'send',
        'alternateSend',
        'backspace',
        'deleteToStart',
        'copy',
        'paste',
        'cut',
        'comma',
        'period',
        'exclamation',
        'quote',
        'screenshot',
      ]) {
        expect(manifest.buttonById('vibe.$app.$action'), isNotNull);
      }
      for (final action in const [
        'comma',
        'period',
        'exclamation',
        'quote',
        'screenshot',
      ]) {
        expect(
          manifest.buttonById('vibe.$app.$action')!.targetType,
          RemoteTargetType.system,
        );
      }
    }
    final synced = DesktopManifest.fromJson(
      DesktopManifest.starter()
          .copyWith(
            applications: DesktopManifest.starter().applications
                .map((app) => app.copyWith(detected: app.id == 'codex'))
                .toList(),
          )
          .toJson(forSync: true),
    );
    expect(synced.layoutById('vibe.claude'), isNotNull);
    expect(synced.applicationById('claude'), isNull);
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

  test('sync preserves one Desktop-observed foreground application', () {
    final original = DesktopManifest.starter();
    final state = original.copyWith(
      applications: original.applications
          .map(
            (application) => application.copyWith(
              detected: application.id == 'vscode',
              running: application.id == 'vscode',
              foreground: application.id == 'vscode',
            ),
          )
          .toList(growable: false),
    );

    final synced = DesktopManifest.fromJson(state.toJson(forSync: true));
    expect(synced.applications.single.id, 'vscode');
    expect(synced.applications.single.foreground, isTrue);
  });

  test(
    'app activation signal round trips without exposing executable data',
    () {
      final manifest = DesktopManifest.starter().copyWith(
        applicationActivationSequence: 4,
        activatedApplicationId: 'finder',
        applications: DesktopManifest.starter().applications
            .map(
              (app) => app.id == 'finder'
                  ? app.copyWith(
                      detected: true,
                      running: true,
                      foreground: true,
                    )
                  : app,
            )
            .toList(growable: false),
      );

      final restored = DesktopManifest.fromJson(manifest.toJson(forSync: true));

      expect(restored.applicationActivationSequence, 4);
      expect(restored.activatedApplicationId, 'finder');
      expect(restored.applicationById('finder')!.foreground, isTrue);
    },
  );

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
