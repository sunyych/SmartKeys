library;

import 'dart:convert';

part 'src/compact_layouts.dart';

const int launcherSlotCount = 12;
const String installedLaunchOnlyLayoutId = 'installed.launch-only';

bool isInstalledApplicationId(String id) =>
    RegExp(r'^installed\.[a-f0-9]{32}$').hasMatch(id);

const installedLaunchOnlyLayout = RemoteShortcutLayout(
  id: installedLaunchOnlyLayoutId,
  name: 'Installed applications',
  kind: RemoteLayoutKind.application,
  buttons: [],
);

/// IDs accepted by the optional authenticated native app-icon resource.
const Set<String> remoteApplicationIconAppIds = <String>{
  'codex',
  'chatgpt',
  'claude',
  'cursor',
  'chrome',
  'edge',
  'firefox',
  'safari',
  'teams',
  'zoom',
  'photoshop',
  'illustrator',
  'vscode',
  'solidworks',
  'premiere',
  'appleMusic',
  'finder',
};

enum RemoteTargetType {
  keyboardShortcut,
  launchApplication,
  voiceInput,
  openUrl,
  macro,
  script,
  system,
}

enum RemoteLayoutKind { keyboard, application, codex }

/// Host families used when resolving portable shortcut defaults.
enum RemoteShortcutPlatform { apple, windows, other }

const int chatGptShortcutsPerPage = 15;
const chatGptNativeVoiceShortcutId = 'chatgpt.startVoice';
const chatGptLocalDictationShortcutId = 'chatgpt.localDictation';
const chatGptSystemDictationShortcutId = 'chatgpt.systemDictation';
const chatGptSystemDictationTarget = 'lumiakeySystemDictation';
const chatGptSystemDictationCapability = 'macos-system-dictation-v1';
const _chatGptLocalDictationTarget = 'lumiakeyLocalDictation';
const _chatGptVoiceKeys = ['CTRL', 'SHIFT', 'V'];
const _explicitChatGptVoiceBinding = 'explicitChatGptVoiceBinding';
const _chatGptVoiceMode = RemoteShortcutButton(
  id: chatGptNativeVoiceShortcutId,
  name: 'Voice Mode',
  icon: 'graphic_eq',
  targetType: RemoteTargetType.keyboardShortcut,
  shortcut: _chatGptVoiceKeys,
  description: 'Start voice chat in ChatGPT.',
);
const _chatGptVoiceSetup = RemoteShortcutButton(
  id: chatGptNativeVoiceShortcutId,
  name: 'Voice Mode',
  icon: 'graphic_eq',
  targetType: RemoteTargetType.keyboardShortcut,
  enabled: false,
  description: 'Set the Voice chat hotkey in ChatGPT, then bind it here.',
);
const _chatGptLocalDictation = RemoteShortcutButton(
  id: chatGptLocalDictationShortcutId,
  name: 'Dictation',
  icon: 'mic_external_on',
  targetType: RemoteTargetType.system,
  target: _chatGptLocalDictationTarget,
  enabled: false,
  description: 'Uses the LumiaKey local dictation controls on the phone.',
);
const _chatGptSystemDictation = RemoteShortcutButton(
  id: chatGptSystemDictationShortcutId,
  name: 'Dictate',
  icon: 'mic_external_on',
  targetType: RemoteTargetType.system,
  target: chatGptSystemDictationTarget,
  description: 'Start macOS Dictation using your system settings.',
);
const _chatGptSystemDictationSetup = RemoteShortcutButton(
  id: chatGptSystemDictationShortcutId,
  name: 'Dictate',
  icon: 'mic_external_on',
  targetType: RemoteTargetType.system,
  target: chatGptSystemDictationTarget,
  enabled: false,
  description:
      'Update LumiaKey Desktop to use macOS Dictation from your phone.',
);
const chatGptFastModeShortcutId = 'chatgpt.codex.fastMode';
const chatGptBranchOffShortcutId = 'chatgpt.codex.branchOff';
const chatGptApproveShortcutId = 'chatgpt.codex.approve';
const chatGptDeclineShortcutId = 'chatgpt.codex.decline';
const chatGptApprovalShortcutIds = {
  chatGptApproveShortcutId,
  chatGptDeclineShortcutId,
};

String confirmedChatGptApprovalShortcutId(String id) => '$id.confirmed';

bool isLegacyCodexLayoutId(String id) => id == 'codex' || id == 'vibe.codex';

/// The disabled wire action is a marker for Full mobile, never a Desktop command.
bool isChatGptLocalDictationShortcut(RemoteShortcutButton button) =>
    button.id == chatGptLocalDictationShortcutId &&
    button.targetType == RemoteTargetType.system &&
    button.target == _chatGptLocalDictationTarget &&
    !button.enabled &&
    button.shortcut.isEmpty;

bool isChatGptSystemDictationShortcut(RemoteShortcutButton button) =>
    button.id == chatGptSystemDictationShortcutId &&
    button.targetType == RemoteTargetType.system &&
    button.target == chatGptSystemDictationTarget;

RemoteShortcutButton chatGptSystemDictationButton({required bool supported}) =>
    supported ? _chatGptSystemDictation : _chatGptSystemDictationSetup;

RemoteShortcutButton chatGptPhoneDictationButton() => _chatGptLocalDictation;

RemoteShortcutLayout projectChatGptSystemDictation(
  RemoteShortcutLayout layout, {
  required RemoteShortcutPlatform platform,
  required bool supported,
}) {
  if (layout.id != 'chatgpt') return layout;
  final isApple = platform == RemoteShortcutPlatform.apple;
  var inserted = false;
  final buttons = <RemoteShortcutButton>[];
  for (final button in layout.buttons) {
    if (button.id == chatGptLocalDictationShortcutId ||
        button.id == chatGptSystemDictationShortcutId) {
      if (!inserted) {
        buttons.add(
          isApple
              ? chatGptSystemDictationButton(supported: supported)
              : chatGptPhoneDictationButton(),
        );
        inserted = true;
      }
    } else {
      buttons.add(button);
    }
  }
  return layout.copyWith(buttons: buttons);
}

bool isUnassignedChatGptShortcut(RemoteShortcutButton button) =>
    const {
      chatGptNativeVoiceShortcutId,
      chatGptFastModeShortcutId,
      chatGptBranchOffShortcutId,
    }.contains(button.id) &&
    button.targetType == RemoteTargetType.keyboardShortcut &&
    !button.enabled &&
    button.shortcut.isEmpty;

/// Fixed page-one controls, ordered by expected everyday use. IDs remain the
/// source of truth so custom names and shortcut bindings do not affect order.
const List<String> _chatGptCommonPrimaryShortcutIds = <String>[
  'chatgpt.newChat',
  'chatgpt.codex.send',
  'chatgpt.codex.copy',
  'chatgpt.codex.paste',
  chatGptFastModeShortcutId,
  chatGptApproveShortcutId,
  chatGptDeclineShortcutId,
  chatGptBranchOffShortcutId,
  chatGptNativeVoiceShortcutId,
  'chatgpt.codex.focusInput',
  'chatgpt.sidebar',
];

const List<String> chatGptPrimaryShortcutIds = <String>[
  ..._chatGptCommonPrimaryShortcutIds,
  'chatgpt.codexMode',
  'chatgpt.codex.alternateSend',
  'chatgpt.codex.backspace',
  'chatgpt.find',
];

const List<String> chatGptRegularPrimaryShortcutIds = <String>[
  ..._chatGptCommonPrimaryShortcutIds,
  chatGptLocalDictationShortcutId,
];

const List<RemoteShortcutButton> _chatGptRegularMiddleRowDefaults = [
  RemoteShortcutButton(
    id: chatGptFastModeShortcutId,
    name: 'Fast Mode',
    icon: 'bolt',
    targetType: RemoteTargetType.keyboardShortcut,
    shortcut: [],
    description: 'Assign a Fast Mode shortcut in the ChatGPT layout.',
    enabled: false,
  ),
  RemoteShortcutButton(
    id: chatGptApproveShortcutId,
    name: 'Approve',
    icon: 'check',
    targetType: RemoteTargetType.keyboardShortcut,
    shortcut: ['ENTER'],
    description: 'Approve the open request in ChatGPT.',
  ),
  RemoteShortcutButton(
    id: chatGptDeclineShortcutId,
    name: 'Decline',
    icon: 'close',
    targetType: RemoteTargetType.keyboardShortcut,
    shortcut: ['ESC'],
    description: 'Decline the open request in ChatGPT.',
  ),
  RemoteShortcutButton(
    id: chatGptBranchOffShortcutId,
    name: 'Branch Off',
    icon: 'call_split',
    targetType: RemoteTargetType.keyboardShortcut,
    shortcut: [],
    description: 'Assign a shortcut to continue this chat in a new chat.',
    enabled: false,
  ),
];

const List<String> chatGptSecondaryShortcutIds = <String>[
  'chatgpt.codex.review',
  'chatgpt.codex.cut',
  'chatgpt.codex.deleteToStart',
  'chatgpt.chatView',
  'chatgpt.codex.project',
  'chatgpt.previousChat',
  'chatgpt.codex.openFolder',
  'chatgpt.codex.commandMenu',
  'chatgpt.codex.terminal',
  'chatgpt.codex.voiceMode',
  'chatgpt.codex.toggleVoiceMode',
  'chatgpt.codex.voiceInput',
  'chatgpt.codex.cancelClear',
  'chatgpt.codex.nextChat',
  'chatgpt.codex.nextProject',
  'chatgpt.nextChat',
  'chatgpt.codex.searchChats',
  'chatgpt.codex.findInChat',
  'chatgpt.codex.screenshot',
  'chatgpt.codex.voice',
  'chatgpt.codex.comma',
  'chatgpt.codex.period',
  'chatgpt.codex.exclamation',
  'chatgpt.codex.quote',
];

/// Orders the ChatGPT layout for fixed-frequency use on phone/tablet pages.
/// This changes presentation order only; IDs, shortcut bindings, and user
/// supplied actions are retained. Review is first among secondary controls.
RemoteShortcutLayout orderChatGptLayout(
  RemoteShortcutLayout layout, {
  int firstPageSize = chatGptShortcutsPerPage,
}) {
  if (layout.id != 'chatgpt') return layout;

  final regular = firstPageSize == regularShortcutCount;
  final primaryIds = regular
      ? chatGptRegularPrimaryShortcutIds
      : chatGptPrimaryShortcutIds.take(firstPageSize);
  final existing = layout.buttons.where(
    (button) => button.id != chatGptLocalDictationShortcutId,
  );
  final buttons = regular
      ? [
          ...existing,
          for (final button in _chatGptRegularMiddleRowDefaults)
            if (!existing.any((candidate) => candidate.id == button.id))
              button,
          if (!existing.any(
            (button) => button.id == chatGptNativeVoiceShortcutId,
          ))
            _chatGptVoiceSetup,
          _chatGptLocalDictation,
        ]
      : existing;
  final rank = {for (final (index, id) in primaryIds.indexed) id: index};
  final primary =
      buttons
          .where((button) => rank.containsKey(button.id))
          .toList(growable: false)
        ..sort((left, right) => rank[left.id]!.compareTo(rank[right.id]!));
  final secondary = buttons
      .where((button) => !rank.containsKey(button.id))
      .toList(growable: true);
  final secondaryIds = [
    chatGptSecondaryShortcutIds.first,
    ...chatGptPrimaryShortcutIds.where((id) => !rank.containsKey(id)),
    ...chatGptSecondaryShortcutIds.skip(1),
  ];
  final secondaryRank = {
    for (final (index, id) in secondaryIds.indexed) id: index,
  };
  secondary.sort((left, right) {
    final leftRank = secondaryRank[left.id] ?? secondaryIds.length;
    final rightRank = secondaryRank[right.id] ?? secondaryIds.length;
    final rankOrder = leftRank.compareTo(rightRank);
    return rankOrder == 0 ? left.id.compareTo(right.id) : rankOrder;
  });
  return layout.copyWith(buttons: [...primary, ...secondary]);
}

/// Replaces the portable PRIMARY modifier with the host's native modifier.
List<String> resolvePrimaryShortcut(
  Iterable<String> keys,
  RemoteShortcutPlatform platform,
) => keys
    .map((key) {
      final normalized = key.trim().toUpperCase();
      if (normalized != 'PRIMARY') return normalized;
      return platform == RemoteShortcutPlatform.apple ? 'COMMAND' : 'CTRL';
    })
    .toList(growable: false);

/// Applies the platform-specific defaults and availability for ChatGPT.
/// Stored layouts are immutable inputs; callers should retain the original so
/// a temporarily hidden platform action does not erase a user's binding.
RemoteShortcutLayout projectChatGptLayout(
  RemoteShortcutLayout layout,
  RemoteShortcutPlatform platform, {
  int firstPageSize = chatGptShortcutsPerPage,
}) {
  if (layout.id != 'chatgpt') return layout;

  const chatViewId = 'chatgpt.chatView';
  const codexModeId = 'chatgpt.codexMode';
  const searchChatsId = 'chatgpt.codex.searchChats';
  final buttons = <RemoteShortcutButton>[];
  for (final button in layout.buttons) {
    if (button.id == chatGptNativeVoiceShortcutId) {
      buttons.add(projectChatGptNativeVoice(button, platform));
      continue;
    }
    if (platform == RemoteShortcutPlatform.other &&
        button.targetType == RemoteTargetType.system) {
      continue;
    }
    if (platform == RemoteShortcutPlatform.windows &&
        button.shortcut.any(
          (key) => const {'COMMAND', 'META', 'WIN'}.contains(key.toUpperCase()),
        )) {
      continue;
    }
    if (button.id == 'chatgpt.codex.voice' &&
        button.targetType == RemoteTargetType.voiceInput) {
      continue;
    }
    // Search Chats is not currently assigned by ChatGPT. Keep a custom user
    // assignment visible, while suppressing the unassigned starter binding.
    if (button.id == searchChatsId &&
        _isUnassignedSearchDefault(button.shortcut)) {
      continue;
    }

    if ((button.id == 'chatgpt.codex.previousChat' &&
            _isDuplicateConversationDefault(button.shortcut, const ['['])) ||
        (button.id == 'chatgpt.codex.nextChat' &&
            _isDuplicateConversationDefault(button.shortcut, const [']']))) {
      continue;
    }

    if (button.id == chatViewId || button.id == codexModeId) {
      final digit = button.id == chatViewId ? '1' : '3';
      final defaultKeys = platform == RemoteShortcutPlatform.apple
          ? <String>['CTRL', digit]
          : <String>['ALT', digit];
      final isKnownDefault =
          _sameShortcut(button.shortcut, ['ALT', digit]) ||
          _sameShortcut(button.shortcut, ['CTRL', digit]);
      if (isKnownDefault) {
        buttons.add(button.copyWith(shortcut: defaultKeys));
        continue;
      }
    }
    buttons.add(
      button.copyWith(
        shortcut: resolvePrimaryShortcut(button.shortcut, platform),
      ),
    );
  }
  return orderChatGptLayout(
    layout.copyWith(buttons: buttons),
    firstPageSize: firstPageSize,
  );
}

/// Records a deliberate binding for a chord used by the old portable default.
/// Keyboard shortcuts ignore [RemoteShortcutButton.target] during execution.
RemoteShortcutButton saveExplicitChatGptVoiceBinding(
  RemoteShortcutButton button,
  RemoteShortcutPlatform platform,
) {
  if (button.id != chatGptNativeVoiceShortcutId ||
      button.targetType != RemoteTargetType.keyboardShortcut) {
    return button;
  }
  return button.copyWith(target: _explicitChatGptVoiceBinding);
}

/// Older bundled layouts stored the macOS binding as a portable value.
/// Retain explicit user bindings except chords that cannot be safely sent.
RemoteShortcutButton projectChatGptNativeVoice(
  RemoteShortcutButton button,
  RemoteShortcutPlatform platform,
) {
  if (button.targetType != RemoteTargetType.keyboardShortcut) {
    return _chatGptVoiceSetup;
  }
  final keys = resolvePrimaryShortcut(button.shortcut, platform);
  final explicitlyBound = button.target == _explicitChatGptVoiceBinding;
  final oldDefault =
      !explicitlyBound &&
      button.name == 'Start Voice Chat' &&
      (button.icon == 'mic' || button.icon.isEmpty) &&
      button.description == 'CTRL + SHIFT + V' &&
      (_sameShortcut(button.shortcut, _chatGptVoiceKeys) ||
          (button.shortcut.isEmpty && !button.enabled));
  final canonicalDefault =
      button.name == _chatGptVoiceMode.name &&
      button.icon == _chatGptVoiceMode.icon &&
      button.description == _chatGptVoiceMode.description &&
      (_sameShortcut(button.shortcut, _chatGptVoiceKeys) ||
          (button.shortcut.isEmpty && !button.enabled));
  final missingDefault =
      button.name == _chatGptVoiceSetup.name &&
      button.icon == _chatGptVoiceSetup.icon &&
      button.shortcut.isEmpty &&
      !button.enabled &&
      button.description == _chatGptVoiceSetup.description;
  final projected = oldDefault
      ? button.shortcut.isEmpty && platform != RemoteShortcutPlatform.apple
            ? _chatGptVoiceSetup
            : _chatGptVoiceMode.copyWith(
                enabled:
                    platform == RemoteShortcutPlatform.apple ||
                    button.enabled,
              )
      : platform == RemoteShortcutPlatform.apple &&
            !explicitlyBound &&
            (canonicalDefault || missingDefault)
      ? _chatGptVoiceMode.copyWith(enabled: true)
      : button;
  final projectedKeys = resolvePrimaryShortcut(projected.shortcut, platform);
  if ((platform != RemoteShortcutPlatform.apple &&
          !explicitlyBound &&
          _sameShortcut(keys, _chatGptVoiceKeys)) ||
      (platform == RemoteShortcutPlatform.windows &&
          keys.any(const {'COMMAND', 'META', 'WIN'}.contains))) {
    return projected.copyWith(
      shortcut: const [],
      enabled: false,
      description: _chatGptVoiceSetup.description,
    );
  }
  return projected.copyWith(shortcut: projectedKeys);
}

RemoteShortcutButton chatGptVoiceDesktopUpdateButton() =>
    _chatGptVoiceSetup.copyWith(
      description: 'Update LumiaKey Desktop to enable Voice Mode from your phone.',
    );

bool _isUnassignedSearchDefault(List<String> keys) => [
  const ['PRIMARY', 'G'],
  const ['CTRL', 'G'],
  const ['COMMAND', 'G'],
  const ['META', 'G'],
].any((candidate) => _sameShortcut(keys, candidate));

bool _isDuplicateConversationDefault(List<String> keys, List<String> ending) =>
    [
      ['PRIMARY', 'SHIFT', ...ending],
      ['CTRL', 'SHIFT', ...ending],
      ['COMMAND', 'SHIFT', ...ending],
      ['META', 'SHIFT', ...ending],
    ].any((candidate) => _sameShortcut(keys, candidate));

bool _sameShortcut(List<String> left, List<String> right) =>
    left.length == right.length &&
    List.generate(
      left.length,
      (index) =>
          left[index].trim().toUpperCase() == right[index].trim().toUpperCase(),
    ).every((same) => same);

enum RemoteActionKind { button, launchApplication, switchProfile }

enum PointerInputKind { move, scroll, button }

class PointerInput {
  const PointerInput.move(this.x, this.y)
    : kind = PointerInputKind.move,
      secondary = null;
  const PointerInput.scroll(this.y)
    : kind = PointerInputKind.scroll,
      x = 0,
      secondary = null;
  const PointerInput.button({required this.secondary})
    : kind = PointerInputKind.button,
      x = 0,
      y = 0;

  final PointerInputKind kind;
  final int x;
  final int y;
  final bool? secondary;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (kind == PointerInputKind.move) 'x': x,
    if (kind != PointerInputKind.button) 'y': y,
    if (kind == PointerInputKind.button) 'secondary': secondary,
  };

  factory PointerInput.fromJson(Map<String, Object?> json) {
    final kind = PointerInputKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => throw const FormatException('Unsupported pointer input'),
    );
    final x = json['x'];
    final y = json['y'];
    final secondary = json['secondary'];
    switch (kind) {
      case PointerInputKind.move:
        if (x is! int || y is! int || x.abs() > 127 || y.abs() > 127) {
          throw const FormatException('Invalid pointer movement');
        }
        return PointerInput.move(x, y);
      case PointerInputKind.scroll:
        if (y is! int || y == 0 || y.abs() > 127) {
          throw const FormatException('Invalid pointer scroll');
        }
        return PointerInput.scroll(y);
      case PointerInputKind.button:
        if (secondary is! bool) {
          throw const FormatException('Invalid pointer button');
        }
        return PointerInput.button(secondary: secondary);
    }
  }
}

class RemoteShortcutButton {
  const RemoteShortcutButton({
    required this.id,
    required this.name,
    required this.icon,
    required this.targetType,
    this.shortcut = const [],
    this.target,
    this.description = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String icon;
  final RemoteTargetType targetType;
  final List<String> shortcut;
  final String? target;
  final String description;
  final bool enabled;

  RemoteShortcutButton copyWith({
    String? name,
    String? icon,
    RemoteTargetType? targetType,
    List<String>? shortcut,
    String? target,
    bool clearTarget = false,
    String? description,
    bool? enabled,
  }) => RemoteShortcutButton(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    targetType: targetType ?? this.targetType,
    shortcut: shortcut ?? this.shortcut,
    target: clearTarget ? null : target ?? this.target,
    description: description ?? this.description,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson({bool includeIcon = true}) => {
    'id': id,
    'name': name,
    'icon': includeIcon ? icon : '',
    'targetType': targetType.name,
    'shortcut': shortcut,
    'target': target,
    'description': description,
    'enabled': enabled,
  };

  factory RemoteShortcutButton.fromJson(Map<String, Object?> json) {
    final targetType = RemoteTargetType.values.firstWhere(
      (value) => value.name == json['targetType'],
      orElse: () => RemoteTargetType.keyboardShortcut,
    );
    return RemoteShortcutButton(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      icon: json['icon']?.toString() ?? '',
      targetType: targetType,
      shortcut: _stringList(json['shortcut']),
      target: _nullableString(json['target']),
      description: json['description']?.toString() ?? '',
      enabled: json['enabled'] is bool ? json['enabled']! as bool : true,
    );
  }
}

class RemoteShortcutLayout {
  const RemoteShortcutLayout({
    required this.id,
    required this.name,
    required this.kind,
    required this.buttons,
  });

  final String id;
  final String name;
  final RemoteLayoutKind kind;
  final List<RemoteShortcutButton> buttons;

  RemoteShortcutLayout copyWith({
    String? name,
    List<RemoteShortcutButton>? buttons,
  }) => RemoteShortcutLayout(
    id: id,
    name: name ?? this.name,
    kind: kind,
    buttons: buttons ?? this.buttons,
  );

  Map<String, Object?> toJson({bool includeIcons = true}) => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'buttons': buttons
        .map((button) => button.toJson(includeIcon: includeIcons))
        .toList(growable: false),
  };

  factory RemoteShortcutLayout.fromJson(Map<String, Object?> json) =>
      RemoteShortcutLayout(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        kind: RemoteLayoutKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => RemoteLayoutKind.keyboard,
        ),
        buttons: _mapList(
          json['buttons'],
        ).map(RemoteShortcutButton.fromJson).toList(growable: false),
      );
}

class RemoteApplication {
  const RemoteApplication({
    required this.id,
    required this.name,
    required this.icon,
    required this.executable,
    required this.layoutId,
    this.detected = false,
    this.running = false,
    this.foreground = false,
    this.launchOnly = false,
  });

  final String id;
  final String name;
  final String icon;
  final String executable;
  final String layoutId;
  final bool detected;
  final bool running;

  /// Desktop-observed foreground state. This is advisory UI state only; it
  /// never grants the phone a new executable capability.
  final bool foreground;

  /// A Desktop-registered launcher entry with no shortcut/voice capability.
  final bool launchOnly;

  RemoteApplication copyWith({
    String? name,
    String? icon,
    String? executable,
    String? layoutId,
    bool? detected,
    bool? running,
    bool? foreground,
    bool? launchOnly,
  }) => RemoteApplication(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    executable: executable ?? this.executable,
    layoutId: layoutId ?? this.layoutId,
    detected: detected ?? this.detected,
    running: running ?? this.running,
    foreground: foreground ?? this.foreground,
    launchOnly: launchOnly ?? this.launchOnly,
  );

  Map<String, Object?> toJson({
    bool includeIcon = true,
    bool forSync = false,
  }) => {
    'id': id,
    'name': name,
    'icon': includeIcon ? icon : '',
    'executable': forSync && launchOnly ? 'Desktop-managed' : executable,
    'layoutId': layoutId,
    'detected': detected,
    'running': running,
    'foreground': foreground,
    'launchOnly': launchOnly,
  };

  factory RemoteApplication.fromJson(Map<String, Object?> json) {
    if (json.containsKey('launchOnly') && json['launchOnly'] is! bool) {
      throw const FormatException('Invalid launch-only application flag');
    }
    return RemoteApplication(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      icon: json['icon']?.toString() ?? '',
      executable: _requiredString(json, 'executable'),
      layoutId: _requiredString(json, 'layoutId'),
      detected: json['detected'] == true,
      running: json['running'] == true,
      foreground: json['foreground'] == true,
      launchOnly: json['launchOnly'] == true,
    );
  }
}

class RemoteProfile {
  const RemoteProfile({
    required this.id,
    required this.name,
    required this.layoutId,
    this.platform,
    this.applicationId,
    this.sourceAppId,
    this.sourceLibraryId,
    this.sourceLibraryVersion,
    this.sourceIconId,
    this.sourceActionHashes = const {},
    this.sourceIconPngBase64,
    this.sourceIconSha256,
  });
  final String id, name, layoutId;
  final String? platform, applicationId;
  // Source metadata is descriptive; it never grants execution authority.
  final String? sourceAppId,
      sourceLibraryId,
      sourceLibraryVersion,
      sourceIconId;
  final Map<String, String> sourceActionHashes;
  final String? sourceIconPngBase64, sourceIconSha256;
  bool get isLibraryProfile => sourceAppId != null;

  void validateSource() {
    final source = [
      sourceAppId,
      sourceLibraryId,
      sourceLibraryVersion,
      sourceIconId,
    ];
    if (source.every((value) => value == null)) {
      if (sourceActionHashes.isNotEmpty ||
          sourceIconPngBase64 != null ||
          sourceIconSha256 != null) {
        throw const FormatException('Orphan library metadata');
      }
      return;
    }
    if (source.any(
          (value) => value == null || value.isEmpty || value.length > 128,
        ) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(sourceAppId!) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(sourceIconId!) ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(sourceLibraryId!) ||
        !const {'macos', 'windows', 'linux'}.contains(platform) ||
        sourceActionHashes.length > 12 ||
        sourceActionHashes.entries.any(
          (entry) =>
              !RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(entry.key) ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value),
        )) {
      throw const FormatException('Invalid library source metadata');
    }
    if ((sourceIconPngBase64 == null) != (sourceIconSha256 == null)) {
      throw const FormatException('Incomplete library artwork');
    }
    if (sourceIconPngBase64 != null) {
      if (sourceIconPngBase64!.length > 87384 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceIconSha256!)) {
        throw const FormatException('Invalid library artwork');
      }
      final bytes = base64Decode(sourceIconPngBase64!);
      if (bytes.length > 65536 ||
          bytes.length < 24 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        throw const FormatException('Invalid library artwork');
      }
    }
  }

  Map<String, Object?> toJson({bool includeIcon = true}) => {
    'id': id,
    'name': name,
    'layoutId': layoutId,
    'platform': platform,
    'applicationId': applicationId,
    if (sourceAppId != null) ...{
      'sourceAppId': sourceAppId,
      'sourceLibraryId': sourceLibraryId,
      'sourceLibraryVersion': sourceLibraryVersion,
      'sourceIconId': sourceIconId,
      'sourceActionHashes': sourceActionHashes,
      if (includeIcon && sourceIconPngBase64 != null)
        'sourceIconPngBase64': sourceIconPngBase64,
      if (includeIcon && sourceIconSha256 != null)
        'sourceIconSha256': sourceIconSha256,
    },
  };

  factory RemoteProfile.fromJson(Map<String, Object?> json) {
    for (final key in const [
      'sourceAppId',
      'sourceLibraryId',
      'sourceLibraryVersion',
      'sourceIconId',
      'sourceIconPngBase64',
      'sourceIconSha256',
    ]) {
      if (json[key] != null && json[key] is! String) {
        throw const FormatException('Invalid library metadata type');
      }
    }
    final rawHashes = json['sourceActionHashes'];
    if (rawHashes != null &&
        (rawHashes is! Map ||
            rawHashes.entries.any(
              (e) => e.key is! String || e.value is! String,
            ))) {
      throw const FormatException('Invalid library action hashes');
    }
    final value = RemoteProfile(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      layoutId: _requiredString(json, 'layoutId'),
      platform: _nullableString(json['platform']),
      applicationId: _nullableString(json['applicationId']),
      sourceAppId: _nullableString(json['sourceAppId']),
      sourceLibraryId: _nullableString(json['sourceLibraryId']),
      sourceLibraryVersion: _nullableString(json['sourceLibraryVersion']),
      sourceIconId: _nullableString(json['sourceIconId']),
      sourceIconPngBase64: _nullableString(json['sourceIconPngBase64']),
      sourceIconSha256: _nullableString(json['sourceIconSha256']),
      sourceActionHashes: rawHashes == null
          ? const {}
          : Map<String, String>.unmodifiable(
              Map<String, String>.from(rawHashes as Map),
            ),
    );
    value.validateSource();
    return value;
  }
}

class RemoteSettings {
  const RemoteSettings({
    this.enableAppsSync = true,
    this.autoLaunchApps = true,
    this.syncIcons = true,
  });

  final bool enableAppsSync;
  final bool autoLaunchApps;
  final bool syncIcons;

  RemoteSettings copyWith({
    bool? enableAppsSync,
    bool? autoLaunchApps,
    bool? syncIcons,
  }) => RemoteSettings(
    enableAppsSync: enableAppsSync ?? this.enableAppsSync,
    autoLaunchApps: autoLaunchApps ?? this.autoLaunchApps,
    syncIcons: syncIcons ?? this.syncIcons,
  );

  Map<String, Object?> toJson() => {
    'enableAppsSync': enableAppsSync,
    'autoLaunchApps': autoLaunchApps,
    'syncIcons': syncIcons,
  };

  factory RemoteSettings.fromJson(Map<String, Object?> json) => RemoteSettings(
    enableAppsSync: json['enableAppsSync'] is bool
        ? json['enableAppsSync']! as bool
        : true,
    autoLaunchApps: json['autoLaunchApps'] is bool
        ? json['autoLaunchApps']! as bool
        : true,
    syncIcons: json['syncIcons'] is bool ? json['syncIcons']! as bool : true,
  );
}

enum RemoteSidebarKind { application, profile }

/// A navigation reference only; it never authorizes launching or input.
class RemoteSidebarItem {
  const RemoteSidebarItem.application(this.id)
    : kind = RemoteSidebarKind.application;
  const RemoteSidebarItem.profile(this.id) : kind = RemoteSidebarKind.profile;
  final RemoteSidebarKind kind;
  final String id;
  String get key => '${kind.name}:$id';
  Map<String, Object?> toJson() => {'kind': kind.name, 'id': id};
  factory RemoteSidebarItem.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (json.length != 2 ||
        id is! String ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid sidebar item');
    }
    return switch (json['kind']) {
      'application' => RemoteSidebarItem.application(id),
      'profile' => RemoteSidebarItem.profile(id),
      _ => throw const FormatException('Unknown sidebar item kind'),
    };
  }
}

class DesktopManifest {
  const DesktopManifest({
    required this.revision,
    required this.currentProfileId,
    required this.settings,
    required this.layouts,
    required this.applications,
    required this.profiles,
    this.computerId,
    this.schemaVersion = 1,
    this.applicationActivationSequence = 0,
    this.activatedApplicationId,
    List<String?>? launcherApplicationIds,
    bool? hasLauncherConfiguration,
    this.sidebarItems,
    this.sidebarShortcutOnlyApplicationIds = const {},
  }) : launcherApplicationIds =
           launcherApplicationIds ??
           const <String?>[
             null,
             null,
             null,
             null,
             null,
             null,
             null,
             null,
             null,
             null,
             null,
             null,
           ],
       hasLauncherConfiguration =
           hasLauncherConfiguration ?? launcherApplicationIds != null;

  final int schemaVersion;
  final int revision;
  final String currentProfileId;
  final RemoteSettings settings;
  final List<RemoteShortcutLayout> layouts;
  final List<RemoteApplication> applications;
  final List<RemoteProfile> profiles;

  /// Stable local Desktop identity used to keep phone preferences associated
  /// with this machine. It never carries the auth token or network address.
  final String? computerId;
  final int applicationActivationSequence;
  final String? activatedApplicationId;

  /// Desktop-configured launcher slots, synced for phone display.
  final List<String?> launcherApplicationIds;

  /// Distinguishes a legacy manifest from an intentionally empty launcher.
  final bool hasLauncherConfiguration;

  /// Null retains the historical automatic sidebar; empty hides optional items.
  final List<RemoteSidebarItem>? sidebarItems;

  /// App Bar selections that open the shortcut panel without activating an app.
  final Set<String> sidebarShortcutOnlyApplicationIds;

  List<RemoteSidebarItem> get defaultSidebarItems {
    final apps = applications.where((app) => !app.launchOnly).toList();
    int rank(String id) => id == 'chatgpt'
        ? 0
        : id == 'chrome'
        ? 1
        : 2;
    apps.sort((a, b) {
      final order = rank(a.id).compareTo(rank(b.id));
      return order != 0
          ? order
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List.unmodifiable([
      for (final app in apps) RemoteSidebarItem.application(app.id),
      for (final profile in profiles.where((p) => p.isLibraryProfile))
        RemoteSidebarItem.profile(profile.id),
    ]);
  }

  List<RemoteSidebarItem> get effectiveSidebarItems =>
      sidebarItems ?? defaultSidebarItems;

  RemoteProfile? get currentProfile =>
      profiles.cast<RemoteProfile?>().firstWhere(
        (profile) => profile?.id == currentProfileId,
        orElse: () => profiles.isEmpty ? null : profiles.first,
      );

  RemoteShortcutLayout? get currentLayout =>
      layoutById(currentProfile?.layoutId ?? 'keyboard');

  RemoteShortcutLayout? layoutById(String id) => layouts
      .cast<RemoteShortcutLayout?>()
      .firstWhere((layout) => layout?.id == id, orElse: () => null);

  RemoteApplication? applicationById(String id) => applications
      .cast<RemoteApplication?>()
      .firstWhere((app) => app?.id == id, orElse: () => null);

  RemoteShortcutButton? buttonById(String id) {
    for (final layout in layouts) {
      for (final button in layout.buttons) {
        if (button.id == id) return button;
      }
    }
    return null;
  }

  DesktopManifest copyWith({
    int? revision,
    String? currentProfileId,
    RemoteSettings? settings,
    List<RemoteShortcutLayout>? layouts,
    List<RemoteApplication>? applications,
    List<RemoteProfile>? profiles,
    String? computerId,
    int? applicationActivationSequence,
    String? activatedApplicationId,
    List<String?>? launcherApplicationIds,
    List<RemoteSidebarItem>? sidebarItems,
    Set<String>? sidebarShortcutOnlyApplicationIds,
    bool clearSidebarConfiguration = false,
  }) => DesktopManifest(
    schemaVersion: schemaVersion,
    revision: revision ?? this.revision,
    currentProfileId: currentProfileId ?? this.currentProfileId,
    settings: settings ?? this.settings,
    layouts: layouts ?? this.layouts,
    applications: applications ?? this.applications,
    profiles: profiles ?? this.profiles,
    computerId: computerId ?? this.computerId,
    applicationActivationSequence:
        applicationActivationSequence ?? this.applicationActivationSequence,
    activatedApplicationId:
        activatedApplicationId ?? this.activatedApplicationId,
    launcherApplicationIds:
        launcherApplicationIds ?? this.launcherApplicationIds,
    hasLauncherConfiguration:
        launcherApplicationIds != null || hasLauncherConfiguration,
    sidebarItems: clearSidebarConfiguration
        ? null
        : sidebarItems ?? this.sidebarItems,
    sidebarShortcutOnlyApplicationIds: clearSidebarConfiguration
        ? const {}
        : sidebarShortcutOnlyApplicationIds ??
              this.sidebarShortcutOnlyApplicationIds,
  );

  Map<String, Object?> toJson({bool forSync = false}) {
    final includeIcons = !forSync || settings.syncIcons;
    final syncedApplications = forSync
        ? settings.enableAppsSync
              ? applications
                    .where(
                      (application) =>
                          application.detected ||
                          launcherApplicationIds.contains(application.id),
                    )
                    .where(
                      (application) =>
                          !application.launchOnly ||
                          launcherApplicationIds.contains(application.id),
                    )
                    .toList(growable: false)
              : const <RemoteApplication>[]
        : applications;
    final syncedActivationApplicationId =
        activatedApplicationId != null &&
            syncedApplications.any((app) => app.id == activatedApplicationId)
        ? activatedApplicationId
        : null;
    final shortcutOnlyIds = forSync
        ? sidebarShortcutOnlyApplicationIds.where(
            (id) =>
                syncedApplications.any(
                  (app) => app.id == id && !app.launchOnly,
                ) &&
                (sidebarItems?.any(
                      (item) =>
                          item.kind == RemoteSidebarKind.application &&
                          item.id == id,
                    ) ??
                    true),
          )
        : sidebarShortcutOnlyApplicationIds;
    return {
      'schemaVersion': schemaVersion,
      'revision': revision,
      if (sidebarItems != null)
        'sidebarItems': sidebarItems!
            .where(
              (item) =>
                  !forSync ||
                  (item.kind == RemoteSidebarKind.application
                      ? syncedApplications.any(
                          (app) => app.id == item.id && !app.launchOnly,
                        )
                      : profiles.any(
                          (profile) =>
                              profile.id == item.id && profile.isLibraryProfile,
                        )),
            )
            .map((item) => item.toJson())
            .toList(growable: false),
      if (shortcutOnlyIds.isNotEmpty)
        'sidebarShortcutOnlyApplicationIds': shortcutOnlyIds.toList(
          growable: false,
        ),
      'currentProfileId': currentProfileId,
      'computerId': computerId,
      'settings': settings.toJson(),
      'layouts': layouts
          .map((layout) => layout.toJson(includeIcons: includeIcons))
          .toList(growable: false),
      'applications': syncedApplications
          .map((app) => app.toJson(includeIcon: includeIcons, forSync: forSync))
          .toList(growable: false),
      'profiles': profiles
          .map((profile) => profile.toJson(includeIcon: includeIcons))
          .toList(),
      'applicationActivationSequence': applicationActivationSequence,
      'activatedApplicationId': syncedActivationApplicationId,
      'launcherApplicationIds': !forSync
          ? launcherApplicationIds
          : settings.enableAppsSync
          ? launcherApplicationIds
                .map(
                  (id) =>
                      syncedApplications.any((app) => app.id == id) ? id : null,
                )
                .toList(growable: false)
          : List<String?>.filled(launcherSlotCount, null),
    };
  }

  factory DesktopManifest.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1) {
      throw const FormatException('Unsupported LumiaKey manifest schema');
    }
    final manifest = DesktopManifest(
      schemaVersion: schemaVersion! as int,
      revision: json['revision'] is int ? json['revision']! as int : 1,
      currentProfileId: _requiredString(json, 'currentProfileId'),
      computerId: _nullableString(json['computerId']),
      settings: RemoteSettings.fromJson(_requiredMap(json, 'settings')),
      layouts: _mapList(
        json['layouts'],
      ).map(RemoteShortcutLayout.fromJson).toList(growable: false),
      applications: _mapList(
        json['applications'],
      ).map(RemoteApplication.fromJson).toList(growable: false),
      profiles: _mapList(
        json['profiles'],
      ).map(RemoteProfile.fromJson).toList(growable: false),
      applicationActivationSequence:
          json['applicationActivationSequence'] is int
          ? json['applicationActivationSequence']! as int
          : 0,
      activatedApplicationId: _nullableString(json['activatedApplicationId']),
      sidebarItems: json.containsKey('sidebarItems')
          ? _sidebarItemsFromJson(json['sidebarItems'])
          : null,
      sidebarShortcutOnlyApplicationIds:
          json.containsKey('sidebarShortcutOnlyApplicationIds')
          ? _sidebarShortcutOnlyIdsFromJson(
              json['sidebarShortcutOnlyApplicationIds'],
            )
          : const {},
      launcherApplicationIds: json.containsKey('launcherApplicationIds')
          ? _launcherSlotsFromJson(json['launcherApplicationIds'])
          : null,
    );
    manifest.validate();
    return manifest;
  }

  static List<RemoteSidebarItem> _sidebarItemsFromJson(Object? raw) {
    if (raw is! List ||
        raw.length > 100 ||
        raw.any(
          (item) => item is! Map || item.keys.any((key) => key is! String),
        )) {
      throw const FormatException('Invalid sidebar navigation');
    }
    return List.unmodifiable(
      raw.map(
        (item) =>
            RemoteSidebarItem.fromJson(Map<String, Object?>.from(item as Map)),
      ),
    );
  }

  static Set<String> _sidebarShortcutOnlyIdsFromJson(Object? raw) {
    if (raw is! List || raw.any((id) => id is! String)) {
      throw const FormatException('Invalid App Bar launch settings');
    }
    final ids = Set<String>.unmodifiable(raw.cast<String>());
    if (ids.length != raw.length) {
      throw const FormatException('Duplicate App Bar launch settings');
    }
    return ids;
  }

  void validate() {
    if (layouts.isEmpty || profiles.isEmpty) {
      throw const FormatException('Manifest must contain layouts and profiles');
    }
    for (final profile in profiles) {
      profile.validateSource();
    }
    if (profiles.fold<int>(
              0,
              (total, p) => total + (p.sourceIconPngBase64?.length ?? 0),
            ) >
            700000 ||
        profiles.where((p) => p.isLibraryProfile).length > 128) {
      throw const FormatException('App library storage limit reached');
    }
    if (profiles.map((profile) => profile.id).toSet().length !=
        profiles.length) {
      throw const FormatException('Profile ids must be unique');
    }
    final items = sidebarItems;
    if (items != null &&
        (items.length > 100 ||
            items.map((item) => item.key).toSet().length != items.length ||
            items.any(
              (item) =>
                  !RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(item.id) ||
                  (item.kind == RemoteSidebarKind.application
                      ? !applications.any(
                          (app) => app.id == item.id && !app.launchOnly,
                        )
                      : !profiles.any(
                          (profile) =>
                              profile.id == item.id && profile.isLibraryProfile,
                        )),
            ))) {
      throw const FormatException(
        'Sidebar contains invalid or launch-only references',
      );
    }
    if (sidebarShortcutOnlyApplicationIds.any(
      (id) => !applications.any((app) => app.id == id && !app.launchOnly),
    )) {
      throw const FormatException(
        'App Bar launch settings contain an invalid application',
      );
    }
    final layoutIds = layouts.map((layout) => layout.id).toSet();
    final appIds = applications.map((app) => app.id).toSet();
    if (appIds.length != applications.length ||
        applications.any(
          (app) =>
              app.launchOnly &&
                  (!isInstalledApplicationId(app.id) ||
                      app.layoutId != installedLaunchOnlyLayoutId) ||
              app.id.startsWith('installed.') && !app.launchOnly,
        )) {
      throw const FormatException(
        'Manifest contains invalid application identities',
      );
    }
    final installedLayout = layoutById(installedLaunchOnlyLayoutId);
    if (installedLayout != null &&
        (installedLayout.kind != RemoteLayoutKind.application ||
            installedLayout.buttons.isNotEmpty)) {
      throw const FormatException(
        'Installed launcher layout must have no actions',
      );
    }
    if (layoutIds.length != layouts.length ||
        profiles.any((profile) => !layoutIds.contains(profile.layoutId)) ||
        applications.any((app) => !layoutIds.contains(app.layoutId)) ||
        !profiles.any((profile) => profile.id == currentProfileId)) {
      throw const FormatException('Manifest contains invalid references');
    }
    if (launcherApplicationIds.length != launcherSlotCount ||
        launcherApplicationIds.any(
          (id) => id != null && !applications.any((app) => app.id == id),
        )) {
      throw const FormatException('Manifest contains invalid launcher slots');
    }
    if (applicationActivationSequence < 0 ||
        (activatedApplicationId != null &&
            !applications.any((app) => app.id == activatedApplicationId))) {
      throw const FormatException('Manifest contains invalid app activation');
    }
    final buttonIds = <String>{};
    if (applications.where((application) => application.foreground).length >
        1) {
      throw const FormatException(
        'Manifest can contain only one foreground app',
      );
    }
    for (final layout in layouts) {
      for (final button in layout.buttons) {
        if (!buttonIds.add(button.id)) {
          throw const FormatException('Button ids must be globally unique');
        }
      }
    }
  }

  /// Twelve-key defaults used by the Regular mobile control surface.
  /// [starter] retains the complete historical action catalog for migration.
  factory DesktopManifest.regularStarter() {
    final catalog = DesktopManifest.starter();
    return catalog.copyWith(
      layouts: catalog.layouts
          .where((layout) => !isLegacyCodexLayoutId(layout.id))
          .map(compactDesktopLayout)
          .toList(growable: false),
    );
  }

  factory DesktopManifest.starter() {
    RemoteShortcutButton shortcut(
      String id,
      String name,
      String icon,
      List<String> keys,
    ) => RemoteShortcutButton(
      id: id,
      name: name,
      icon: icon,
      targetType: RemoteTargetType.keyboardShortcut,
      shortcut: keys,
      description: keys.join(' + '),
    );

    RemoteShortcutLayout appLayout(
      String id,
      String name,
      List<RemoteShortcutButton> buttons,
    ) => RemoteShortcutLayout(
      id: id,
      name: name,
      kind: RemoteLayoutKind.application,
      buttons: buttons,
    );

    final keyboard = RemoteShortcutLayout(
      id: 'keyboard',
      name: 'Keyboard',
      kind: RemoteLayoutKind.keyboard,
      buttons: [
        shortcut('keyboard.copy', 'Copy', 'copy', ['PRIMARY', 'C']),
        shortcut('keyboard.paste', 'Paste', 'paste', ['PRIMARY', 'V']),
        shortcut('keyboard.undo', 'Undo', 'undo', ['PRIMARY', 'Z']),
        shortcut('keyboard.redo', 'Redo', 'redo', ['PRIMARY', 'SHIFT', 'Z']),
        shortcut('keyboard.cut', 'Cut', 'cut', ['PRIMARY', 'X']),
        shortcut('keyboard.play', 'Play', 'play', ['SPACE']),
        shortcut('keyboard.pause', 'Pause', 'pause', ['SPACE']),
        shortcut('keyboard.next', 'Next', 'skip_next', ['CTRL', 'RIGHT']),
        shortcut('keyboard.previous', 'Previous', 'skip_previous', [
          'CTRL',
          'LEFT',
        ]),
      ],
    );
    final vscode = appLayout('app.vscode', 'VSCode', [
      shortcut('vscode.open', 'Open', 'folder_open', ['PRIMARY', 'O']),
      shortcut('vscode.save', 'Save', 'save', ['PRIMARY', 'S']),
      shortcut('vscode.terminal', 'Terminal', 'terminal', ['CTRL', '`']),
      shortcut('vscode.search', 'Search', 'search', ['PRIMARY', 'SHIFT', 'F']),
      shortcut('vscode.git', 'Git', 'source_control', ['CTRL', 'SHIFT', 'G']),
      shortcut('vscode.run', 'Run', 'play', ['CTRL', 'F5']),
      shortcut('vscode.debug', 'Debug', 'bug', ['F5']),
      shortcut('vscode.comment', 'Comment', 'comment', ['PRIMARY', '/']),
      shortcut('vscode.format', 'Format', 'format', ['SHIFT', 'ALT', 'F']),
    ]);
    final photoshop = appLayout('app.photoshop', 'Photoshop', [
      shortcut('photoshop.open', 'Open', 'folder_open', ['PRIMARY', 'O']),
      shortcut('photoshop.save', 'Save', 'save', ['PRIMARY', 'S']),
      shortcut('photoshop.undo', 'Undo', 'undo', ['PRIMARY', 'Z']),
      shortcut('photoshop.copy', 'Copy', 'copy', ['PRIMARY', 'C']),
      shortcut('photoshop.paste', 'Paste', 'paste', ['PRIMARY', 'V']),
      shortcut('photoshop.transform', 'Transform', 'transform', [
        'PRIMARY',
        'T',
      ]),
    ]);
    final premiere = appLayout('app.premiere', 'Premiere', [
      shortcut('premiere.save', 'Save', 'save', ['PRIMARY', 'S']),
      shortcut('premiere.play', 'Play', 'play', ['SPACE']),
      shortcut('premiere.cut', 'Add Edit', 'cut', ['PRIMARY', 'K']),
      shortcut('premiere.export', 'Export', 'export', ['PRIMARY', 'M']),
    ]);
    final chrome = appLayout('app.chrome', 'Chrome', [
      shortcut('chrome.newTab', 'New Tab', 'add', ['PRIMARY', 'T']),
      shortcut('chrome.closeTab', 'Close Tab', 'close', ['PRIMARY', 'W']),
      shortcut('chrome.bookmark', 'Bookmark', 'bookmark', ['PRIMARY', 'D']),
      shortcut('chrome.previousTab', 'Previous Tab', 'arrow_back', [
        'CTRL',
        'SHIFT',
        'TAB',
      ]),
      shortcut('chrome.nextTab', 'Next Tab', 'arrow_next', ['CTRL', 'TAB']),
      shortcut('chrome.back', 'Go Back', 'arrow_back', ['BROWSER_BACK']),
      shortcut('chrome.forward', 'Go Forward', 'arrow_next', [
        'BROWSER_FORWARD',
      ]),
      shortcut('chrome.copy', 'Copy', 'copy', ['PRIMARY', 'C']),
      shortcut('chrome.paste', 'Paste', 'paste', ['PRIMARY', 'V']),
      const RemoteShortcutButton(
        id: 'chrome.passwordManager',
        name: 'Passwords',
        icon: 'password',
        targetType: RemoteTargetType.openUrl,
        target: 'https://passwords.google.com/',
        description: 'Open Google Password Manager',
      ),
      shortcut('chrome.playPause', 'Play / Pause', 'play', ['SPACE']),
      shortcut('chrome.stop', 'Stop', 'stop', ['ESC']),
      shortcut('chrome.mute', 'Mute', 'volume_off', ['M']),
      shortcut('chrome.refresh', 'Refresh', 'refresh', ['PRIMARY', 'R']),
      shortcut('chrome.address', 'Address', 'link', ['PRIMARY', 'L']),
    ]);
    RemoteShortcutLayout browserLayout(String appId, String name) =>
        appLayout('app.$appId', name, [
          shortcut('$appId.newTab', 'New Tab', 'add', ['PRIMARY', 'T']),
          shortcut('$appId.closeTab', 'Close Tab', 'close', ['PRIMARY', 'W']),
          shortcut('$appId.previousTab', 'Previous Tab', 'arrow_back', [
            'CTRL',
            'SHIFT',
            'TAB',
          ]),
          shortcut('$appId.nextTab', 'Next Tab', 'arrow_forward', [
            'CTRL',
            'TAB',
          ]),
          shortcut('$appId.address', 'Address', 'link', ['PRIMARY', 'L']),
          shortcut('$appId.find', 'Find on Page', 'search', ['PRIMARY', 'F']),
          shortcut('$appId.back', 'Go Back', 'arrow_back', ['ALT', 'LEFT']),
          shortcut('$appId.forward', 'Go Forward', 'arrow_forward', [
            'ALT',
            'RIGHT',
          ]),
          shortcut('$appId.refresh', 'Refresh', 'refresh', ['PRIMARY', 'R']),
          shortcut('$appId.bookmark', 'Bookmark', 'bookmark', ['PRIMARY', 'D']),
        ]);
    final firefox = browserLayout('firefox', 'Firefox');
    final edge = browserLayout('edge', 'Microsoft Edge');
    final safari = browserLayout('safari', 'Safari');
    RemoteShortcutLayout meetingLayout(
      String appId,
      String name,
      List<String> mute,
      List<String> video,
      List<String> hand,
      List<String>? chat,
    ) => appLayout('app.$appId', name, [
      shortcut('$appId.mute', 'Mute / Unmute', 'mic_off', mute),
      shortcut('$appId.video', 'Camera On / Off', 'videocam', video),
      shortcut('$appId.hand', 'Raise / Lower Hand', 'pan_tool', hand),
      if (chat != null) shortcut('$appId.chat', 'Meeting Chat', 'chat', chat),
    ]);
    final teams = meetingLayout(
      'teams',
      'Microsoft Teams',
      ['PRIMARY', 'SHIFT', 'M'],
      ['PRIMARY', 'SHIFT', 'O'],
      ['PRIMARY', 'SHIFT', 'K'],
      null,
    );
    final zoom = meetingLayout(
      'zoom',
      'Zoom',
      ['ALT', 'A'],
      ['ALT', 'V'],
      ['ALT', 'Y'],
      ['ALT', 'H'],
    );
    final illustrator = appLayout('app.illustrator', 'Illustrator', [
      shortcut('illustrator.open', 'Open', 'folder_open', ['PRIMARY', 'O']),
      shortcut('illustrator.save', 'Save', 'save', ['PRIMARY', 'S']),
      shortcut('illustrator.undo', 'Undo', 'undo', ['PRIMARY', 'Z']),
      shortcut('illustrator.group', 'Group', 'group', ['PRIMARY', 'G']),
    ]);
    final solidworks = appLayout('app.solidworks', 'SolidWorks', [
      shortcut('solidworks.open', 'Open', 'folder_open', ['CTRL', 'O']),
      shortcut('solidworks.save', 'Save', 'save', ['CTRL', 'S']),
      shortcut('solidworks.rebuild', 'Rebuild', 'refresh', ['CTRL', 'B']),
      shortcut('solidworks.forceRebuild', 'Force Rebuild', 'build', [
        'CTRL',
        'Q',
      ]),
    ]);
    final codex = RemoteShortcutLayout(
      id: 'codex',
      name: 'Codex',
      kind: RemoteLayoutKind.codex,
      buttons: [
        shortcut('codex.focusInput', 'Focus Input', 'center_focus_strong', [
          'ESC',
        ]),
        const RemoteShortcutButton(
          id: 'codex.voice',
          name: 'Voice Input',
          icon: 'mic',
          targetType: RemoteTargetType.voiceInput,
          description: 'Start Codex dictation',
        ),
        shortcut('codex.newChat', 'New Chat', 'add', ['PRIMARY', 'N']),
        shortcut('codex.previousConversation', 'Previous Chat', 'arrow_up', [
          'PRIMARY',
          'SHIFT',
          '[',
        ]),
        shortcut('codex.nextConversation', 'Next Chat', 'arrow_down', [
          'PRIMARY',
          'SHIFT',
          ']',
        ]),
        shortcut('codex.send', 'Send', 'send', ['ENTER']),
        shortcut('codex.searchChats', 'Search Chats', 'search', [
          'PRIMARY',
          'G',
        ]),
        shortcut('codex.findInChat', 'Find in Chat', 'find_in_page', [
          'PRIMARY',
          'F',
        ]),
        shortcut('codex.openFolder', 'Open Folder', 'folder_open', [
          'PRIMARY',
          'O',
        ]),
        shortcut('codex.commandMenu', 'Command Menu', 'menu', [
          'PRIMARY',
          'SHIFT',
          'P',
        ]),
        shortcut('codex.terminal', 'Terminal', 'terminal', ['CTRL', '`']),
        shortcut('codex.review', 'Review', 'difference', [
          'CTRL',
          'SHIFT',
          'G',
        ]),
        shortcut('codex.back', 'Back', 'arrow_back', ['PRIMARY', '[']),
        shortcut('codex.forward', 'Forward', 'arrow_next', ['PRIMARY', ']']),
        shortcut('codex.sidebar', 'Sidebar', 'menu_open', ['PRIMARY', 'B']),
      ],
    );
    RemoteShortcutLayout vibeLayout(
      String id,
      String name,
      List<RemoteShortcutButton> buttons,
    ) => RemoteShortcutLayout(
      id: 'vibe.$id',
      name: 'Vibe Coding · $name',
      kind: RemoteLayoutKind.application,
      buttons: buttons,
    );
    RemoteShortcutButton vibeShortcut(
      String app,
      String action,
      String name,
      String icon,
      List<String> keys,
    ) => shortcut('vibe.$app.$action', name, icon, keys);
    RemoteShortcutButton deleteToStartButton(
      String app,
    ) => RemoteShortcutButton(
      id: 'vibe.$app.deleteToStart',
      name: 'Delete to Line Start',
      icon: 'format_clear',
      targetType: RemoteTargetType.keyboardShortcut,
      shortcut: ['SHIFT', 'HOME'],
      description:
          'Select to the start of the current line, then delete. Desktop checks focus before both steps.',
    );
    RemoteShortcutButton vibeSystemButton(
      String app,
      String action,
      String name,
      String icon,
    ) => RemoteShortcutButton(
      id: 'vibe.$app.$action',
      name: name,
      icon: icon,
      targetType: RemoteTargetType.system,
      target: action,
      description:
          'Desktop built-in $name action. Fixed action; no custom text or script.',
    );
    List<RemoteShortcutButton> vibeEditingButtons(String app) => [
      vibeShortcut(app, 'send', 'Send', 'send', ['ENTER']),
      vibeShortcut(
        app,
        'alternateSend',
        'Alternate Send (app-defined)',
        'keyboard_return',
        ['PRIMARY', 'ENTER'],
      ),
      vibeShortcut(app, 'backspace', 'Backspace', 'backspace', ['BACKSPACE']),
      deleteToStartButton(app),
      vibeShortcut(app, 'copy', 'Copy', 'copy', ['PRIMARY', 'C']),
      vibeShortcut(app, 'paste', 'Paste', 'paste', ['PRIMARY', 'V']),
      vibeShortcut(app, 'cut', 'Cut', 'content_cut', ['PRIMARY', 'X']),
      vibeSystemButton(app, 'comma', 'Insert Comma', 'text_fields'),
      vibeSystemButton(app, 'period', 'Insert Period', 'text_fields'),
      vibeSystemButton(app, 'exclamation', 'Insert Exclamation', 'text_fields'),
      vibeSystemButton(app, 'quote', 'Insert Quotation Marks', 'format_quote'),
      vibeSystemButton(app, 'screenshot', 'Screenshot Selection', 'screenshot'),
    ];
    final vibeCodex = vibeLayout('codex', 'Codex', [
      vibeShortcut('codex', 'project', 'Open Project', 'folder_open', [
        'PRIMARY',
        'ALT',
        'SHIFT',
        'O',
      ]),
      vibeShortcut('codex', 'newChat', 'New Chat', 'add', ['PRIMARY', 'N']),
      vibeShortcut(
        'codex',
        'focusInput',
        'Focus Input',
        'center_focus_strong',
        ['ESC'],
      ),
      vibeShortcut('codex', 'previousChat', 'Previous Chat', 'arrow_back', [
        'PRIMARY',
        'SHIFT',
        '[',
      ]),
      vibeShortcut('codex', 'nextChat', 'Next Chat', 'arrow_forward', [
        'PRIMARY',
        'SHIFT',
        ']',
      ]),
      vibeShortcut('codex', 'terminal', 'Toggle Terminal', 'terminal', [
        'CTRL',
        '`',
      ]),
      vibeShortcut('codex', 'review', 'Review', 'difference', [
        'CTRL',
        'SHIFT',
        'G',
      ]),
      ...vibeEditingButtons('codex'),
    ]);
    RemoteShortcutButton chatGptCodexButton(
      RemoteShortcutButton button,
      String action,
    ) => RemoteShortcutButton(
      id: 'chatgpt.codex.$action',
      name: button.name,
      icon: button.icon,
      targetType: button.targetType,
      shortcut: button.shortcut,
      target: button.target,
      description: button.description,
      enabled: button.enabled,
    );
    final chatgpt = appLayout('chatgpt', 'ChatGPT', [
      shortcut('chatgpt.chatView', 'Chat View', 'chat', ['ALT', '1']),
      shortcut('chatgpt.codexMode', 'Codex Mode', 'code', ['ALT', '3']),
      _chatGptVoiceMode,
      _chatGptLocalDictation,
      ..._chatGptRegularMiddleRowDefaults,
      shortcut('chatgpt.newChat', 'New Chat', 'add', ['PRIMARY', 'N']),
      shortcut('chatgpt.previousChat', 'Previous Chat', 'arrow_back', [
        'CTRL',
        'SHIFT',
        'TAB',
      ]),
      shortcut('chatgpt.nextChat', 'Next Chat', 'arrow_forward', [
        'CTRL',
        'TAB',
      ]),
      shortcut('chatgpt.find', 'Find', 'search', ['PRIMARY', 'F']),
      shortcut('chatgpt.sidebar', 'Show / Hide Sidebar', 'menu_open', [
        'PRIMARY',
        'B',
      ]),
      ...codex.buttons
          .where(
            (button) => !const {
              'codex.newChat',
              'codex.focusInput',
              'codex.previousConversation',
              'codex.nextConversation',
              'codex.send',
              'codex.findInChat',
              'codex.terminal',
              'codex.review',
              'codex.sidebar',
            }.contains(button.id),
          )
          .map(
            (button) => chatGptCodexButton(
              button,
              button.id.substring('codex.'.length),
            ),
          ),
      ...vibeCodex.buttons
          .where((button) => button.id != 'vibe.codex.newChat')
          .map(
            (button) => chatGptCodexButton(
              button,
              button.id.substring('vibe.codex.'.length),
            ),
          ),
    ]);
    final vibeClaude = vibeLayout('claude', 'Claude', [
      RemoteShortcutButton(
        id: 'vibe.claude.project',
        name: 'Choose Project',
        icon: 'folder_open',
        targetType: RemoteTargetType.keyboardShortcut,
        shortcut: ['PRIMARY', 'N'],
        description:
            'Start a new Claude Code session, then choose its project folder.',
      ),
      vibeShortcut('claude', 'stop', 'Stop Response', 'stop', ['ESC']),
      vibeShortcut('claude', 'diff', 'Show Diff', 'difference', [
        'PRIMARY',
        'SHIFT',
        'D',
      ]),
      vibeShortcut('claude', 'terminal', 'Toggle Terminal', 'terminal', [
        'CTRL',
        '`',
      ]),
      vibeShortcut('claude', 'shortcuts', 'Keyboard Shortcuts', 'keyboard', [
        'PRIMARY',
        '/',
      ]),
      vibeShortcut(
        'claude',
        'previousSession',
        'Previous Session',
        'arrow_back',
        ['CTRL', 'SHIFT', 'TAB'],
      ),
      vibeShortcut('claude', 'nextSession', 'Next Session', 'arrow_forward', [
        'CTRL',
        'TAB',
      ]),
      ...vibeEditingButtons('claude'),
    ]);
    final vibeCursor = vibeLayout('cursor', 'Cursor', [
      RemoteShortcutButton(
        id: 'vibe.cursor.project',
        name: 'Choose Project',
        icon: 'folder_open',
        targetType: RemoteTargetType.keyboardShortcut,
        shortcut: ['PRIMARY', 'SHIFT', 'P'],
        description:
            'Opens Cursor Command Palette. Choose File: Open Folder or File: Open Recent; for direct opening, bind a dedicated Cursor shortcut and edit this button in Desktop > Shortcut Layout > Vibe Coding.',
      ),
      vibeShortcut('cursor', 'newChat', 'New Chat', 'add', ['PRIMARY', 'R']),
      vibeShortcut('cursor', 'cancel', 'Cancel', 'cancel', [
        'PRIMARY',
        'SHIFT',
        'BACKSPACE',
      ]),
      vibeShortcut('cursor', 'addContext', 'Add Selection to Chat', 'add_box', [
        'PRIMARY',
        'SHIFT',
        'L',
      ]),
      vibeShortcut('cursor', 'previousChat', 'Previous Chat', 'arrow_back', [
        'PRIMARY',
        '[',
      ]),
      vibeShortcut('cursor', 'nextChat', 'Next Chat', 'arrow_forward', [
        'PRIMARY',
        ']',
      ]),
      vibeShortcut(
        'cursor',
        'agentPanel',
        'Toggle Agent Panel',
        'view_sidebar',
        ['PRIMARY', 'I'],
      ),
      ...vibeEditingButtons('cursor'),
    ]);
    final appleMusic = appLayout('app.appleMusic', 'Apple Music', [
      shortcut('appleMusic.playPause', 'Play / Pause', 'play', ['SPACE']),
      shortcut('appleMusic.next', 'Next Song', 'skip_next', [
        'PRIMARY',
        'RIGHT',
      ]),
      shortcut('appleMusic.previous', 'Previous Song', 'skip_previous', [
        'PRIMARY',
        'LEFT',
      ]),
      shortcut('appleMusic.volumeUp', 'Volume Up', 'volume_up', [
        'PRIMARY',
        'UP',
      ]),
      shortcut('appleMusic.volumeDown', 'Volume Down', 'volume_down', [
        'PRIMARY',
        'DOWN',
      ]),
      shortcut('appleMusic.search', 'Search', 'search', ['PRIMARY', 'F']),
    ]);
    final finder = appLayout('app.finder', 'Finder', [
      shortcut('finder.newWindow', 'New Window', 'add', ['PRIMARY', 'N']),
      shortcut('finder.newFolder', 'New Folder', 'create_new_folder', [
        'PRIMARY',
        'SHIFT',
        'N',
      ]),
      shortcut('finder.open', 'Open', 'folder_open', ['PRIMARY', 'O']),
      shortcut('finder.getInfo', 'Get Info', 'info', ['PRIMARY', 'I']),
      shortcut('finder.copy', 'Copy', 'copy', ['PRIMARY', 'C']),
      shortcut('finder.paste', 'Paste', 'paste', ['PRIMARY', 'V']),
      shortcut('finder.trash', 'Move to Trash', 'delete', [
        'PRIMARY',
        'BACKSPACE',
      ]),
      shortcut('finder.search', 'Search', 'search', ['PRIMARY', 'F']),
      shortcut('finder.back', 'Back', 'arrow_back', ['PRIMARY', '[']),
      shortcut('finder.forward', 'Forward', 'arrow_next', ['PRIMARY', ']']),
      shortcut('finder.iconView', 'Icon View', 'grid_view', ['PRIMARY', '1']),
      shortcut('finder.listView', 'List View', 'view_list', ['PRIMARY', '2']),
      shortcut('finder.columnView', 'Column View', 'view_column', [
        'PRIMARY',
        '3',
      ]),
      shortcut('finder.galleryView', 'Gallery View', 'image', ['PRIMARY', '4']),
      shortcut('finder.quickLook', 'Quick Look', 'visibility', ['SPACE']),
    ]);
    return DesktopManifest(
      revision: 1,
      currentProfileId: 'default',
      settings: const RemoteSettings(),
      layouts: [
        keyboard,
        vscode,
        photoshop,
        premiere,
        chrome,
        illustrator,
        solidworks,
        codex,
        chatgpt,
        vibeCodex,
        vibeClaude,
        vibeCursor,
        edge,
        firefox,
        safari,
        teams,
        zoom,
        appleMusic,
        finder,
      ],
      applications: const [
        RemoteApplication(
          id: 'chatgpt',
          name: 'ChatGPT',
          icon: 'chat',
          executable: 'ChatGPT',
          layoutId: 'chatgpt',
        ),
        RemoteApplication(
          id: 'claude',
          name: 'Claude Code',
          icon: 'terminal',
          executable: 'Claude',
          layoutId: 'vibe.claude',
        ),
        RemoteApplication(
          id: 'cursor',
          name: 'Cursor',
          icon: 'code',
          executable: 'Cursor',
          layoutId: 'vibe.cursor',
        ),
        RemoteApplication(
          id: 'photoshop',
          name: 'Photoshop',
          icon: 'image',
          executable: 'Adobe Photoshop',
          layoutId: 'app.photoshop',
        ),
        RemoteApplication(
          id: 'illustrator',
          name: 'Illustrator',
          icon: 'draw',
          executable: 'Adobe Illustrator',
          layoutId: 'app.illustrator',
        ),
        RemoteApplication(
          id: 'vscode',
          name: 'VSCode',
          icon: 'code',
          executable: 'Visual Studio Code',
          layoutId: 'app.vscode',
        ),
        RemoteApplication(
          id: 'solidworks',
          name: 'SolidWorks',
          icon: 'view_in_ar',
          executable: 'SLDWORKS.exe',
          layoutId: 'app.solidworks',
        ),
        RemoteApplication(
          id: 'premiere',
          name: 'Premiere',
          icon: 'movie',
          executable: 'Adobe Premiere Pro',
          layoutId: 'app.premiere',
        ),
        RemoteApplication(
          id: 'chrome',
          name: 'Chrome',
          icon: 'language',
          executable: 'Google Chrome',
          layoutId: 'app.chrome',
        ),
        RemoteApplication(
          id: 'firefox',
          name: 'Firefox',
          icon: 'language',
          executable: 'firefox',
          layoutId: 'app.firefox',
        ),
        RemoteApplication(
          id: 'edge',
          name: 'Microsoft Edge',
          icon: 'language',
          executable: 'microsoft-edge',
          layoutId: 'app.edge',
        ),
        RemoteApplication(
          id: 'safari',
          name: 'Safari',
          icon: 'language',
          executable: 'Safari',
          layoutId: 'app.safari',
        ),
        RemoteApplication(
          id: 'teams',
          name: 'Microsoft Teams',
          icon: 'groups',
          executable: 'Microsoft Teams',
          layoutId: 'app.teams',
        ),
        RemoteApplication(
          id: 'zoom',
          name: 'Zoom',
          icon: 'videocam',
          executable: 'zoom.us',
          layoutId: 'app.zoom',
        ),
        RemoteApplication(
          id: 'appleMusic',
          name: 'Apple Music',
          icon: 'music',
          executable: 'Music',
          layoutId: 'app.appleMusic',
        ),
        RemoteApplication(
          id: 'finder',
          name: 'Finder',
          icon: 'folder_open',
          executable: 'Finder',
          layoutId: 'app.finder',
        ),
      ],
      profiles: const [
        RemoteProfile(id: 'default', name: 'Default', layoutId: 'keyboard'),
      ],
    );
  }
}

class RemoteActionRequest {
  const RemoteActionRequest._({
    required this.kind,
    this.buttonId,
    this.applicationId,
    this.profileId,
  });

  const RemoteActionRequest.button(String buttonId)
    : this._(kind: RemoteActionKind.button, buttonId: buttonId);

  const RemoteActionRequest.launchApplication(String applicationId)
    : this._(
        kind: RemoteActionKind.launchApplication,
        applicationId: applicationId,
      );

  const RemoteActionRequest.switchProfile(String profileId)
    : this._(kind: RemoteActionKind.switchProfile, profileId: profileId);

  final RemoteActionKind kind;
  final String? buttonId;
  final String? applicationId;
  final String? profileId;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'buttonId': buttonId,
    'applicationId': applicationId,
    'profileId': profileId,
  };

  factory RemoteActionRequest.fromJson(Map<String, Object?> json) {
    const allowed = {'kind', 'buttonId', 'applicationId', 'profileId'};
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Remote actions accept identifiers only');
    }
    final kind = RemoteActionKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => throw const FormatException('Unsupported remote action'),
    );
    final selected = switch (kind) {
      RemoteActionKind.button => 'buttonId',
      RemoteActionKind.launchApplication => 'applicationId',
      RemoteActionKind.switchProfile => 'profileId',
    };
    final value = json[selected];
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > 256 ||
        value.codeUnits.any((unit) => unit < 32 || unit == 127) ||
        allowed
            .where((key) => key != 'kind' && key != selected)
            .any((key) => json[key] != null)) {
      throw const FormatException('Invalid remote action identifier');
    }
    return switch (kind) {
      RemoteActionKind.button => RemoteActionRequest.button(
        _requiredString(json, 'buttonId'),
      ),
      RemoteActionKind.launchApplication =>
        RemoteActionRequest.launchApplication(
          _requiredString(json, 'applicationId'),
        ),
      RemoteActionKind.switchProfile => RemoteActionRequest.switchProfile(
        _requiredString(json, 'profileId'),
      ),
    };
  }
}

List<String> parseShortcut(String text) => text
    .split('+')
    .map((key) => key.trim().toUpperCase())
    .where((key) => key.isNotEmpty)
    .toList(growable: false);

String formatShortcut(Iterable<String> keys) => keys.join(' + ');

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing $key');
  return value;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('Missing $key');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) {
        return entry.map((key, value) => MapEntry(key.toString(), value));
      })
      .toList(growable: false);
}

List<String> _stringList(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

List<String?> _launcherSlotsFromJson(Object? value) {
  if (value is! List ||
      (value.length != 8 && value.length != launcherSlotCount) ||
      value.any((id) => id != null && (id is! String || id.isEmpty))) {
    throw const FormatException('Invalid launcher slots');
  }
  return List<String?>.unmodifiable([
    ...value.cast<String?>(),
    for (var index = value.length; index < launcherSlotCount; index++) null,
  ]);
}
