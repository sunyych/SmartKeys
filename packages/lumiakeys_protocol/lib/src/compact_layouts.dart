part of '../lumiakeys_protocol.dart';

const int regularShortcutCount = 12;
const generalCloseAppShortcutId = 'keyboard.closeApp';
const _closeAppDefault = 'CLOSE_APP';
const _legacyGeneralCloseTarget = 'lumiakeyLegacyGeneralCloseApp';
const _generalCloseAppShortcut = RemoteShortcutButton(
  id: generalCloseAppShortcutId,
  name: 'Close App',
  icon: 'close',
  targetType: RemoteTargetType.keyboardShortcut,
  shortcut: [_closeAppDefault],
  description: 'Close the active application.',
);

List<String> generalCloseAppChord(RemoteShortcutPlatform platform) =>
    platform == RemoteShortcutPlatform.apple
        ? const ['COMMAND', 'Q']
        : const ['ALT', 'F4'];

/// Identifies the unedited Escape button shipped by legacy General layouts.
bool isStockLegacyGeneralEscape(RemoteShortcutButton button) =>
    button.id == 'keyboard.escape' &&
    button.name == 'Escape' &&
    button.icon == 'close' &&
    button.targetType == RemoteTargetType.keyboardShortcut &&
    button.target == null &&
    button.shortcut.length == 1 &&
    button.shortcut.single == 'ESC' &&
    button.description == 'ESC' &&
    button.enabled;

/// Identifies only the phone-only Close projection of a legacy Escape button.
bool isProjectedLegacyGeneralClose(RemoteShortcutButton button) =>
    button.id == 'keyboard.escape' &&
    button.name == 'Close App' &&
    button.icon == 'close' &&
    button.targetType == RemoteTargetType.keyboardShortcut &&
    button.target == _legacyGeneralCloseTarget &&
    button.description == 'Close the active application.' &&
    button.enabled;

/// Gives legacy phone clients the Close App presentation while retaining the
/// raw button ID so the old host's allowlisted shortcut action can execute it.
RemoteShortcutLayout projectLegacyGeneralEscapeForPhone(
  RemoteShortcutLayout layout,
  RemoteShortcutPlatform platform,
) {
  if (layout.id != 'keyboard' ||
      platform == RemoteShortcutPlatform.other ||
      layout.buttons.any((button) => button.id == generalCloseAppShortcutId)) {
    return layout;
  }
  final chord = generalCloseAppChord(platform);
  return layout.copyWith(
    buttons: [
      for (final button in layout.buttons)
        if (isStockLegacyGeneralEscape(button))
          button.copyWith(
            name: 'Close App',
            shortcut: chord,
            target: _legacyGeneralCloseTarget,
            description: 'Close the active application.',
          )
        else
          button,
    ],
  );
}

/// Resolves the portable General default before displaying or sending it.
RemoteShortcutLayout projectGeneralLayout(
  RemoteShortcutLayout layout,
  RemoteShortcutPlatform platform,
) {
  if (layout.id != 'keyboard') return layout;
  return layout.copyWith(
    buttons: [
      for (final button in layout.buttons)
        if (button.id == generalCloseAppShortcutId &&
            button.targetType == RemoteTargetType.keyboardShortcut &&
            _sameShortcut(button.shortcut, const [_closeAppDefault]))
          button.copyWith(
            shortcut: generalCloseAppChord(platform),
          )
        else
          button,
    ],
  );
}

/// Updates the shipped Escape button in place while preserving saved edits.
RemoteShortcutLayout migrateLegacyGeneralEscape(RemoteShortcutLayout layout) {
  if (layout.id != 'keyboard' ||
      layout.buttons.any((button) => button.id == generalCloseAppShortcutId)) {
    return layout;
  }
  return layout.copyWith(
    buttons: [
      for (final button in layout.buttons)
        if (isStockLegacyGeneralEscape(button))
          _generalCloseAppShortcut
        else
          button,
    ],
  );
}

/// Selects built-in twelve-key defaults, retaining catalog action IDs/bindings.
/// Only use for defaults; saved custom layouts keep their full contents.
RemoteShortcutLayout compactDesktopLayout(RemoteShortcutLayout layout) {
  if (layout.id == 'keyboard') return _regularGeneralLayout(layout);
  if (layout.id == 'chatgpt') {
    return orderChatGptLayout(layout, firstPageSize: regularShortcutCount);
  }
  final priorities = layout.id.startsWith('vibe.')
      ? [
          for (final action in const [
            'project',
            'newChat',
            'focusInput',
            'agentPanel',
            'cancel',
            'addContext',
            'send',
            'alternateSend',
            'copy',
            'paste',
            'cut',
            'backspace',
            'deleteToStart',
            'previousChat',
            'nextChat',
            'previousSession',
            'nextSession',
            'review',
            'terminal',
          ])
            '${layout.id}.$action',
        ]
      : switch (layout.id) {
          'app.chrome' => const [
            'chrome.newTab',
            'chrome.closeTab',
            'chrome.previousTab',
            'chrome.nextTab',
            'chrome.back',
            'chrome.forward',
            'chrome.copy',
            'chrome.paste',
            'chrome.address',
            'chrome.refresh',
            'chrome.bookmark',
            'chrome.passwordManager',
          ],
          'app.finder' => const [
            'finder.newWindow',
            'finder.newFolder',
            'finder.open',
            'finder.copy',
            'finder.paste',
            'finder.trash',
            'finder.search',
            'finder.back',
            'finder.forward',
            'finder.iconView',
            'finder.listView',
            'finder.quickLook',
          ],
          _ => const <String>[],
        };
  final byId = {for (final button in layout.buttons) button.id: button};
  final selected = <RemoteShortcutButton>[
    for (final id in priorities)
      if (byId[id] != null) byId[id]!,
  ].take(regularShortcutCount).toList(growable: true);
  for (final button in layout.buttons) {
    if (selected.length == regularShortcutCount) break;
    if (!selected.any((candidate) => candidate.id == button.id)) {
      selected.add(button);
    }
  }
  return layout.copyWith(buttons: selected);
}

RemoteShortcutLayout _regularGeneralLayout(RemoteShortcutLayout catalog) {
  final byId = {for (final button in catalog.buttons) button.id: button};
  RemoteShortcutButton shortcut(
    String id,
    String name,
    String icon,
    List<String> keys,
  ) =>
      byId[id] ??
      RemoteShortcutButton(
        id: id,
        name: name,
        icon: icon,
        targetType: RemoteTargetType.keyboardShortcut,
        shortcut: keys,
        description: keys.join(' + '),
      );
  RemoteShortcutButton media(String action, String name, String icon) =>
      RemoteShortcutButton(
        id: 'keyboard.$action',
        name: name,
        icon: icon,
        targetType: RemoteTargetType.system,
        target: action,
        description: 'Control the computer output: $name',
      );
  return catalog.copyWith(
    name: 'General',
    buttons: [
      shortcut('keyboard.copy', 'Copy', 'copy', ['PRIMARY', 'C']),
      shortcut('keyboard.paste', 'Paste', 'paste', ['PRIMARY', 'V']),
      shortcut('keyboard.cut', 'Cut', 'content_cut', ['PRIMARY', 'X']),
      shortcut('keyboard.undo', 'Undo', 'undo', ['PRIMARY', 'Z']),
      shortcut('keyboard.redo', 'Redo', 'redo', ['PRIMARY', 'SHIFT', 'Z']),
      shortcut('keyboard.selectAll', 'Select All', 'select_all', [
        'PRIMARY',
        'A',
      ]),
      shortcut('keyboard.delete', 'Delete', 'backspace', ['BACKSPACE']),
      _generalCloseAppShortcut,
      media('mute', 'Mute', 'volume_off'),
      media('volumeDown', 'Volume Down', 'volume_down'),
      media('volumeUp', 'Volume Up', 'volume_up'),
      media('playPause', 'Play / Pause', 'play'),
    ],
  );
}
