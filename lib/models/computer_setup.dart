import 'package:flutter/foundation.dart';

import 'config.dart';

enum ComputerMode { disconnected, standalone, advanced }

enum ComputerOperatingSystem {
  windows('Windows'),
  linux('Linux'),
  macos('macOS');

  const ComputerOperatingSystem(this.label);

  final String label;

  static ComputerOperatingSystem? fromJson(Object? value) {
    for (final operatingSystem in values) {
      if (operatingSystem.name == value) return operatingSystem;
    }
    return null;
  }
}

@immutable
class ComputerTarget {
  const ComputerTarget({
    required this.id,
    required this.name,
    required this.mode,
    required this.isApple,
    this.operatingSystem,
  });

  ComputerTarget withOperatingSystem(ComputerOperatingSystem operatingSystem) =>
      ComputerTarget(
        id: id,
        name: name,
        mode: mode,
        isApple: operatingSystem == ComputerOperatingSystem.macos,
        operatingSystem: operatingSystem,
      );

  final String id;
  final String name;
  final ComputerMode mode;
  final bool isApple;
  final ComputerOperatingSystem? operatingSystem;

  @override
  bool operator ==(Object other) =>
      other is ComputerTarget &&
      other.id == id &&
      other.name == name &&
      other.mode == mode &&
      other.isApple == isApple &&
      other.operatingSystem == operatingSystem;

  @override
  int get hashCode => Object.hash(id, name, mode, isApple, operatingSystem);
}

enum ComputerAppCategory { browser, meetings, vibeCoding, chat, other }

@immutable
class ComputerApplication {
  const ComputerApplication({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;
  final ComputerAppCategory category;
}

const computerApplications = <ComputerApplication>[
  ComputerApplication(
    id: 'chrome',
    name: 'Chrome',
    category: ComputerAppCategory.browser,
  ),
  ComputerApplication(
    id: 'firefox',
    name: 'Firefox',
    category: ComputerAppCategory.browser,
  ),
  ComputerApplication(
    id: 'edge',
    name: 'Microsoft Edge',
    category: ComputerAppCategory.browser,
  ),
  ComputerApplication(
    id: 'safari',
    name: 'Safari',
    category: ComputerAppCategory.browser,
  ),
  ComputerApplication(
    id: 'teams',
    name: 'Microsoft Teams',
    category: ComputerAppCategory.meetings,
  ),
  ComputerApplication(
    id: 'zoom',
    name: 'Zoom',
    category: ComputerAppCategory.meetings,
  ),
  ComputerApplication(
    id: 'chatgpt',
    name: 'ChatGPT',
    category: ComputerAppCategory.chat,
  ),
  ComputerApplication(
    id: 'claude',
    name: 'Claude',
    category: ComputerAppCategory.vibeCoding,
  ),
  ComputerApplication(
    id: 'cursor',
    name: 'Cursor',
    category: ComputerAppCategory.vibeCoding,
  ),
];

List<ComputerApplication> computerApplicationsForOperatingSystem(
  ComputerOperatingSystem? operatingSystem,
) => computerApplications
    .where(
      (application) =>
          isComputerApplicationSupportedOn(application, operatingSystem),
    )
    .toList(growable: false);

bool isComputerApplicationSupportedOn(
  ComputerApplication application,
  ComputerOperatingSystem? operatingSystem,
) =>
    (application.id != 'safari' ||
    operatingSystem == ComputerOperatingSystem.macos);

String canonicalComputerApplicationId(String id) =>
    id == 'codex' ? 'chatgpt' : id;

String canonicalComputerShortcutId(String appId, String actionId) {
  if (actionId == 'codex.sidebar' ||
      appId == 'codex' && actionId == 'sidebar') {
    return 'sidebar';
  }
  if (appId != 'codex') return actionId;
  if (actionId == 'launch') return 'codexMode';
  if (actionId == 'newChat') return 'newChat';
  return 'codex.$actionId';
}

ComputerApplication? computerApplicationById(String id) =>
    computerApplications.cast<ComputerApplication?>().firstWhere(
      (application) => application?.id == canonicalComputerApplicationId(id),
      orElse: () => null,
    );

@immutable
class ComputerShortcut {
  const ComputerShortcut({
    required this.id,
    required this.label,
    required this.requiredForSetup,
  });

  final String id;
  final String label;
  final bool requiredForSetup;
}

const _browserShortcuts = <ComputerShortcut>[
  ComputerShortcut(id: 'launch', label: 'Launch app', requiredForSetup: true),
  ComputerShortcut(id: 'newTab', label: 'New tab', requiredForSetup: false),
  ComputerShortcut(id: 'closeTab', label: 'Close tab', requiredForSetup: false),
  ComputerShortcut(
    id: 'previousTab',
    label: 'Previous tab',
    requiredForSetup: false,
  ),
  ComputerShortcut(id: 'nextTab', label: 'Next tab', requiredForSetup: false),
  ComputerShortcut(id: 'back', label: 'Back', requiredForSetup: false),
  ComputerShortcut(id: 'forward', label: 'Forward', requiredForSetup: false),
  ComputerShortcut(id: 'refresh', label: 'Refresh', requiredForSetup: false),
  ComputerShortcut(
    id: 'addressBar',
    label: 'Focus address bar',
    requiredForSetup: false,
  ),
];

const _meetingShortcuts = <ComputerShortcut>[
  ComputerShortcut(id: 'launch', label: 'Launch app', requiredForSetup: true),
  ComputerShortcut(
    id: 'mute',
    label: 'Toggle microphone',
    requiredForSetup: true,
  ),
  ComputerShortcut(
    id: 'camera',
    label: 'Toggle camera',
    requiredForSetup: true,
  ),
  ComputerShortcut(
    id: 'raiseHand',
    label: 'Raise or lower hand',
    requiredForSetup: true,
  ),
];

const _vibeShortcuts = <ComputerShortcut>[
  ComputerShortcut(id: 'launch', label: 'Launch app', requiredForSetup: true),
  ComputerShortcut(
    id: 'voiceMode',
    label: 'Start voice mode',
    requiredForSetup: true,
  ),
  ComputerShortcut(
    id: 'toggleVoiceMode',
    label: 'Toggle voice mode',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'voiceInput',
    label: 'Start voice input',
    requiredForSetup: true,
  ),
  ComputerShortcut(
    id: 'cancelClear',
    label: 'Cancel or clear',
    requiredForSetup: true,
  ),
  ComputerShortcut(
    id: 'previousChat',
    label: 'Previous conversation',
    requiredForSetup: true,
  ),
  ComputerShortcut(
    id: 'nextChat',
    label: 'Next conversation',
    requiredForSetup: true,
  ),
  ComputerShortcut(
    id: 'nextProject',
    label: 'Next project',
    requiredForSetup: true,
  ),
  ComputerShortcut(id: 'send', label: 'Send', requiredForSetup: false),
  ComputerShortcut(
    id: 'alternateSend',
    label: 'Alternate send',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'backspace',
    label: 'Backspace',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'deleteToStart',
    label: 'Delete to line start',
    requiredForSetup: false,
  ),
  ComputerShortcut(id: 'copy', label: 'Copy', requiredForSetup: false),
  ComputerShortcut(id: 'paste', label: 'Paste', requiredForSetup: false),
  ComputerShortcut(id: 'cut', label: 'Cut', requiredForSetup: false),
  ComputerShortcut(id: 'comma', label: 'Insert comma', requiredForSetup: false),
  ComputerShortcut(
    id: 'period',
    label: 'Insert period',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'exclamation',
    label: 'Insert exclamation mark',
    requiredForSetup: false,
  ),
  ComputerShortcut(id: 'quote', label: 'Insert quote', requiredForSetup: false),
  ComputerShortcut(
    id: 'screenshot',
    label: 'Screenshot selection',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'newChat',
    label: 'New conversation',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'terminal',
    label: 'Toggle terminal',
    requiredForSetup: false,
  ),
];

const _chatShortcuts = <ComputerShortcut>[
  ComputerShortcut(
    id: 'launch',
    label: 'Open ChatGPT Chat Bar',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'chatView',
    label: 'Open Chat view',
    requiredForSetup: false,
  ),
  ComputerShortcut(id: 'newChat', label: 'New chat', requiredForSetup: false),
  ComputerShortcut(
    id: 'startVoice',
    label: 'Start voice chat',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'stopVoice',
    label: 'Stop voice chat',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'previousChat',
    label: 'Previous chat',
    requiredForSetup: false,
  ),
  ComputerShortcut(id: 'nextChat', label: 'Next chat', requiredForSetup: false),
  ComputerShortcut(id: 'find', label: 'Find', requiredForSetup: false),
  ComputerShortcut(
    id: 'sidebar',
    label: 'Show or hide sidebar',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codexMode',
    label: 'Open Codex mode',
    requiredForSetup: false,
  ),
  ..._codexModeShortcuts,
];

const _codexModeShortcuts = <ComputerShortcut>[
  ComputerShortcut(
    id: 'codex.project',
    label: 'Codex · Open project',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.focusInput',
    label: 'Codex · Focus input',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.searchChats',
    label: 'Codex · Search chats',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.findInChat',
    label: 'Codex · Find in chat',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.openFolder',
    label: 'Codex · Open folder',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.commandMenu',
    label: 'Codex · Command menu',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.voiceMode',
    label: 'Codex · Start voice mode',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.toggleVoiceMode',
    label: 'Codex · Toggle voice mode',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.voiceInput',
    label: 'Codex · Start voice input',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.cancelClear',
    label: 'Codex · Cancel or clear',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.previousChat',
    label: 'Codex · Previous conversation',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.nextChat',
    label: 'Codex · Next conversation',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.nextProject',
    label: 'Codex · Next project',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.send',
    label: 'Codex · Send',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.alternateSend',
    label: 'Codex · Alternate send',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.backspace',
    label: 'Codex · Backspace',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.deleteToStart',
    label: 'Codex · Delete to line start',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.copy',
    label: 'Codex · Copy',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.paste',
    label: 'Codex · Paste',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.cut',
    label: 'Codex · Cut',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.comma',
    label: 'Codex · Insert comma',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.period',
    label: 'Codex · Insert period',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.exclamation',
    label: 'Codex · Insert exclamation mark',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.quote',
    label: 'Codex · Insert quote',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.screenshot',
    label: 'Codex · Screenshot selection',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.terminal',
    label: 'Codex · Toggle terminal',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.review',
    label: 'Codex · Review',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.back',
    label: 'Codex · Back',
    requiredForSetup: false,
  ),
  ComputerShortcut(
    id: 'codex.forward',
    label: 'Codex · Forward',
    requiredForSetup: false,
  ),
];

List<ComputerShortcut> computerShortcutsFor(ComputerAppCategory category) =>
    switch (category) {
      ComputerAppCategory.browser => _browserShortcuts,
      ComputerAppCategory.meetings => _meetingShortcuts,
      ComputerAppCategory.vibeCoding => _vibeShortcuts,
      ComputerAppCategory.chat => _chatShortcuts,
      ComputerAppCategory.other => const [],
    };

String? defaultComputerShortcut(
  ComputerTarget target,
  ComputerApplication application,
  String actionId,
) {
  final primary = target.isApple ? 'Command' : 'Ctrl';
  if (application.category == ComputerAppCategory.vibeCoding) {
    if (application.id == 'cursor') {
      return switch (actionId) {
        'toggleVoiceMode' => '$primary+Shift+Space',
        'cancelClear' => '$primary+Shift+Backspace',
        'previousChat' => '$primary+[',
        'nextChat' => '$primary+]',
        'newChat' => '$primary+N',
        _ => switch (actionId) {
          'send' => 'Enter',
          'alternateSend' => '$primary+Enter',
          'backspace' => 'Backspace',
          'copy' => '$primary+C',
          'paste' => '$primary+V',
          'cut' => '$primary+X',
          'comma' => 'Comma',
          'period' => 'Period',
          'exclamation' => 'Shift+1',
          'quote' => "Shift+'",
          'screenshot' => target.isApple ? 'Command+Shift+4' : null,
          _ => null,
        },
      };
    }
    return switch (actionId) {
      'send' => 'Enter',
      'alternateSend' => '$primary+Enter',
      'backspace' => 'Backspace',
      'copy' => '$primary+C',
      'paste' => '$primary+V',
      'cut' => '$primary+X',
      'comma' => 'Comma',
      'period' => 'Period',
      'exclamation' => 'Shift+1',
      'quote' => "Shift+'",
      'screenshot' => target.isApple ? 'Command+Shift+4' : null,
      _ => null,
    };
  }
  if (application.category == ComputerAppCategory.meetings) {
    if (application.id == 'teams') {
      final primaryKey = target.isApple ? 'Command' : 'Ctrl';
      return switch (actionId) {
        'mute' => '$primaryKey+Shift+M',
        'camera' => '$primaryKey+Shift+O',
        'raiseHand' => '$primaryKey+Shift+K',
        _ => null,
      };
    }
    if (application.id == 'zoom') {
      if (target.isApple) {
        return switch (actionId) {
          'mute' => 'Command+Shift+A',
          'camera' => 'Command+Shift+V',
          'raiseHand' => 'Option+Y',
          _ => null,
        };
      }
      return switch (actionId) {
        'mute' => 'Alt+A',
        'camera' => 'Alt+V',
        'raiseHand' => 'Alt+Y',
        _ => null,
      };
    }
  }
  if (application.category == ComputerAppCategory.chat) {
    if (actionId.startsWith('codex.')) {
      if (target.operatingSystem == null) return null;
      if (actionId == 'codex.searchChats') return null;
      if (actionId == 'codex.screenshot') {
        return switch (target.operatingSystem) {
          ComputerOperatingSystem.macos => 'Command+Shift+4',
          ComputerOperatingSystem.windows => 'Win+Shift+S',
          ComputerOperatingSystem.linux || null => null,
        };
      }
      return _defaultCodexComputerShortcut(primary, actionId.substring(6));
    }
    // These defaults follow OpenAI's documented macOS app shortcuts. The
    // Windows app does not document a corresponding voice-chat chord, so leave
    // it unset for the user to supply if their installed version exposes one.
    if (target.operatingSystem == ComputerOperatingSystem.windows) {
      return switch (actionId) {
        'chatView' => 'Alt+1',
        'newChat' => 'Ctrl+N',
        'previousChat' => 'Ctrl+Shift+Tab',
        'nextChat' => 'Ctrl+Tab',
        'find' => 'Ctrl+F',
        'sidebar' => 'Ctrl+B',
        'codexMode' => 'Alt+3',
        _ => null,
      };
    }
    if (target.operatingSystem == ComputerOperatingSystem.linux) {
      return switch (actionId) {
        'chatView' => 'Alt+1',
        'newChat' => 'Ctrl+N',
        'previousChat' => 'Ctrl+Shift+Tab',
        'nextChat' => 'Ctrl+Tab',
        'find' => 'Ctrl+F',
        'sidebar' => 'Ctrl+B',
        'codexMode' => 'Alt+3',
        _ => null,
      };
    }
    if (target.operatingSystem != ComputerOperatingSystem.macos) return null;
    return switch (actionId) {
      // This opens ChatGPT's configurable Chat Bar, not its full main window.
      // A user's explicit full-window launch binding can override it.
      'launch' => 'Option+Space',
      'chatView' => 'Ctrl+1',
      'newChat' => 'Command+N',
      'startVoice' => 'Ctrl+Shift+V',
      'previousChat' => 'Ctrl+Shift+Tab',
      'nextChat' => 'Ctrl+Tab',
      'find' => 'Command+F',
      'sidebar' => 'Command+B',
      'codexMode' => 'Ctrl+3',
      _ => null,
    };
  }
  if (application.category != ComputerAppCategory.browser) return null;
  return switch (actionId) {
    'newTab' => '$primary+T',
    'closeTab' => '$primary+W',
    'previousTab' => 'Ctrl+Shift+Tab',
    'nextTab' => 'Ctrl+Tab',
    'back' => target.isApple ? 'Command+[' : 'Alt+Left',
    'forward' => target.isApple ? 'Command+]' : 'Alt+Right',
    'refresh' => '$primary+R',
    'addressBar' => '$primary+L',
    _ => null,
  };
}

String? _defaultCodexComputerShortcut(String primary, String actionId) =>
    switch (actionId) {
      'project' => '$primary+Alt+Shift+O',
      'focusInput' => 'Escape',
      'searchChats' => '$primary+G',
      'findInChat' => '$primary+F',
      'openFolder' => '$primary+O',
      'commandMenu' => '$primary+Shift+P',
      'send' => 'Enter',
      'alternateSend' => '$primary+Enter',
      'backspace' => 'Backspace',
      'copy' => '$primary+C',
      'paste' => '$primary+V',
      'cut' => '$primary+X',
      'comma' => 'Comma',
      'period' => 'Period',
      'exclamation' => 'Shift+1',
      'quote' => "Shift+'",
      'nextProject' => '$primary+Alt+Shift+O',
      'terminal' => 'Ctrl+`',
      'review' => 'Ctrl+Shift+G',
      'back' => '$primary+[',
      'forward' => '$primary+]',
      'sidebar' => '$primary+B',
      _ => null,
    };

List<String> _canonicalizeApplicationIds(Iterable<String> ids) =>
    List.unmodifiable(
      ids
          .map(canonicalComputerApplicationId)
          .toSet()
          .where((id) => RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(id)),
    );

Map<String, Map<String, String>> _canonicalizeBindings(
  Map<String, Map<String, String>> input,
) {
  final normalized = <String, Map<String, String>>{};
  // Fold legacy Codex settings in first so explicit ChatGPT settings win on
  // shared actions such as New Chat.
  final entries = input.entries.toList()
    ..sort(
      (a, b) => (a.key == 'codex' ? 0 : 1).compareTo(b.key == 'codex' ? 0 : 1),
    );
  for (final entry in entries) {
    final appId = canonicalComputerApplicationId(entry.key);
    final app = computerApplicationById(appId);
    if (app == null || !RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(appId)) {
      continue;
    }
    final appBindings = normalized.putIfAbsent(appId, () => {});
    for (final binding in entry.value.entries) {
      final actionId = canonicalComputerShortcutId(entry.key, binding.key);
      if (computerShortcutsFor(
        app.category,
      ).any((action) => action.id == actionId)) {
        appBindings[actionId] = binding.value.trim();
      }
    }
  }
  return {
    for (final entry in normalized.entries)
      entry.key: Map<String, String>.unmodifiable(entry.value),
  };
}

@immutable
class ComputerSetup {
  ComputerSetup({
    required List<String> applicationIds,
    Map<String, Map<String, String>> bindings = const {},
    this.operatingSystem,
    this.setupComplete = true,
  }) : applicationIds = _canonicalizeApplicationIds(applicationIds),
       bindings = Map.unmodifiable(_canonicalizeBindings(bindings));

  final List<String> applicationIds;
  final Map<String, Map<String, String>> bindings;
  final ComputerOperatingSystem? operatingSystem;
  final bool setupComplete;

  String? bindingFor(String appId, String actionId) =>
      bindings[appId]?[actionId];

  factory ComputerSetup.fromJson(Map<String, dynamic>? json) {
    final rawBindings = json?['bindings'];
    final rawApplications = json?['applicationIds'];
    final parsedBindings = <String, Map<String, String>>{};
    if (rawBindings is Map) {
      for (final entry in rawBindings.entries) {
        if (entry.value is! Map) continue;
        parsedBindings[entry.key.toString()] = {
          for (final binding in (entry.value as Map).entries)
            if (binding.value is String)
              binding.key.toString(): binding.value! as String,
        };
      }
    }
    return ComputerSetup(
      applicationIds: (rawApplications is List ? rawApplications : const [])
          .map((id) => id.toString())
          .toList(),
      bindings: parsedBindings,
      operatingSystem: ComputerOperatingSystem.fromJson(
        json?['operatingSystem'],
      ),
      setupComplete: json?['setupComplete'] != false,
    );
  }

  Map<String, Object?> toJson() => {
    'applicationIds': applicationIds,
    'bindings': bindings,
    'operatingSystem': operatingSystem?.name,
    'setupComplete': setupComplete,
  };
}

/// Convert the setup wizard's `Ctrl+Shift+P` style chord into Android's
/// keyboard-HID representation. Unknown keys and malformed chords are rejected.
HidAction? parseComputerShortcut(String chord) {
  const modifierAliases = {
    'CTRL': 'LEFT_CTRL',
    'CONTROL': 'LEFT_CTRL',
    'SHIFT': 'LEFT_SHIFT',
    'ALT': 'LEFT_ALT',
    'OPTION': 'LEFT_ALT',
    'CMD': 'LEFT_META',
    'COMMAND': 'LEFT_META',
    'META': 'LEFT_META',
    'WIN': 'LEFT_META',
    'WINDOWS': 'LEFT_META',
  };
  const specialKeys = {
    'ENTER': 'KEY_ENTER',
    'RETURN': 'KEY_ENTER',
    'ESC': 'KEY_ESCAPE',
    'ESCAPE': 'KEY_ESCAPE',
    'BACKSPACE': 'KEY_BACKSPACE',
    'TAB': 'KEY_TAB',
    'SPACE': 'KEY_SPACE',
    'HOME': 'KEY_HOME',
    'END': 'KEY_END',
    'DELETE': 'KEY_DELETE',
    'INSERT': 'KEY_INSERT',
    'UP': 'KEY_UP',
    'DOWN': 'KEY_DOWN',
    'LEFT': 'KEY_LEFT',
    'RIGHT': 'KEY_RIGHT',
    'PAGEUP': 'KEY_PAGE_UP',
    'PAGEDOWN': 'KEY_PAGE_DOWN',
    '`': 'KEY_GRAVE',
    '[': 'KEY_LEFT_BRACKET',
    ']': 'KEY_RIGHT_BRACKET',
    '-': 'KEY_MINUS',
    '=': 'KEY_EQUALS',
    ',': 'KEY_COMMA',
    'COMMA': 'KEY_COMMA',
    '.': 'KEY_PERIOD',
    'PERIOD': 'KEY_PERIOD',
    '/': 'KEY_SLASH',
    "'": 'KEY_APOSTROPHE',
  };
  final parts = chord
      .split('+')
      .map((part) => part.trim())
      .toList(growable: false);
  if (parts.isEmpty || parts.any((part) => part.isEmpty)) return null;
  final modifiers = <String>[];
  for (final part in parts.take(parts.length - 1)) {
    final modifier = modifierAliases[part.toUpperCase()];
    if (modifier == null || modifiers.contains(modifier)) return null;
    modifiers.add(modifier);
  }
  final rawKey = parts.last.toUpperCase();
  final key =
      specialKeys[rawKey] ??
      (RegExp(r'^[A-Z]$').hasMatch(rawKey) ||
              RegExp(r'^[0-9]$').hasMatch(rawKey) ||
              RegExp(r'^F([1-9]|1[0-2])$').hasMatch(rawKey)
          ? 'KEY_$rawKey'
          : null);
  if (key == null) return null;
  return HidAction(
    type: ActionType.keyboard,
    keyCode: key,
    modifiers: List.unmodifiable(modifiers),
  );
}
