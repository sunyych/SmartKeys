import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('Regular defaults validate and fit a twelve-cell control surface', () {
    final manifest = DesktopManifest.regularStarter();
    manifest.validate();
    for (final layout in manifest.layouts) {
      expect(
        layout.buttons.length,
        lessThanOrEqualTo(regularShortcutCount),
        reason: layout.id,
      );
      expect(
        layout.buttons.map((button) => button.id).toSet().length,
        layout.buttons.length,
      );
    }
    expect(manifest.layoutById('keyboard')!.buttons, hasLength(12));
    expect(manifest.layoutById('app.chrome')!.buttons, hasLength(12));
    expect(manifest.layoutById('chatgpt')!.buttons, hasLength(12));
  });
  test('General offers clipboard, editing and fixed system media actions', () {
    final general = DesktopManifest.regularStarter().layoutById('keyboard')!;
    expect(general.name, 'General');
    expect(
      general.buttons.map((button) => button.id),
      containsAll([
        'keyboard.copy',
        'keyboard.paste',
        'keyboard.cut',
        'keyboard.undo',
        'keyboard.redo',
        'keyboard.selectAll',
        'keyboard.mute',
        'keyboard.volumeDown',
        'keyboard.volumeUp',
        'keyboard.playPause',
      ]),
    );
    for (final action in ['mute', 'volumeDown', 'volumeUp', 'playPause']) {
      final button = general.buttons.singleWhere(
        (button) => button.id == 'keyboard.$action',
      );
      expect(button.targetType, RemoteTargetType.system);
      expect(button.target, action);
    }
  });
  test(
    'Chrome keeps navigation, clipboard and address controls in twelve keys',
    () {
      final chrome = DesktopManifest.regularStarter().layoutById('app.chrome')!;
      expect(
        chrome.buttons.map((button) => button.id),
        containsAll([
          'chrome.address',
          'chrome.refresh',
          'chrome.previousTab',
          'chrome.nextTab',
          'chrome.back',
          'chrome.forward',
          'chrome.copy',
          'chrome.paste',
        ]),
      );
      expect(
        DesktopManifest.starter().layoutById('app.chrome')!.buttons.length,
        greaterThan(12),
        reason:
            'The canonical historical catalog remains available for migration.',
      );
    },
  );
  test(
    'Vibe defaults retain send and clipboard rather than truncating the tail',
    () {
      final manifest = DesktopManifest.regularStarter();
      for (final app in ['codex', 'claude', 'cursor']) {
        final layout = manifest.layoutById('vibe.$app')!;
        expect(layout.buttons.length, lessThanOrEqualTo(12));
        expect(
          layout.buttons.map((button) => button.id),
          containsAll(['vibe.$app.send', 'vibe.$app.copy', 'vibe.$app.paste']),
        );
      }
    },
  );
  test('platform projection never expands the compact ChatGPT defaults', () {
    final layout = DesktopManifest.regularStarter().layoutById('chatgpt')!;
    for (final platform in RemoteShortcutPlatform.values) {
      final projected = projectChatGptLayout(layout, platform);
      expect(projected.buttons.length, lessThanOrEqualTo(12));
      expect(
        projected.buttons.map((button) => button.id),
        containsAll([
          'chatgpt.newChat',
          'chatgpt.codex.copy',
          'chatgpt.codex.paste',
        ]),
      );
    }
  });
}
