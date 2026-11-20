part of '../lumiakeys_protocol.dart';

const int regularShortcutCount = 12;

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
      shortcut('keyboard.escape', 'Escape', 'close', ['ESC']),
      media('mute', 'Mute', 'volume_off'),
      media('volumeDown', 'Volume Down', 'volume_down'),
      media('volumeUp', 'Volume Up', 'volume_up'),
      media('playPause', 'Play / Pause', 'play'),
    ],
  );
}
