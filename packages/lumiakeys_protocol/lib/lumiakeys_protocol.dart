library;

enum RemoteTargetType {
  keyboardShortcut,
  launchApplication,
  voiceInput,
  openUrl,
  macro,
  script,
}

enum RemoteLayoutKind { keyboard, application, codex }

enum RemoteActionKind { button, launchApplication, switchProfile }

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

  RemoteApplication copyWith({
    String? name,
    String? icon,
    String? executable,
    String? layoutId,
    bool? detected,
    bool? running,
    bool? foreground,
  }) => RemoteApplication(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    executable: executable ?? this.executable,
    layoutId: layoutId ?? this.layoutId,
    detected: detected ?? this.detected,
    running: running ?? this.running,
    foreground: foreground ?? this.foreground,
  );

  Map<String, Object?> toJson({bool includeIcon = true}) => {
    'id': id,
    'name': name,
    'icon': includeIcon ? icon : '',
    'executable': executable,
    'layoutId': layoutId,
    'detected': detected,
    'running': running,
    'foreground': foreground,
  };

  factory RemoteApplication.fromJson(Map<String, Object?> json) =>
      RemoteApplication(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        icon: json['icon']?.toString() ?? '',
        executable: _requiredString(json, 'executable'),
        layoutId: _requiredString(json, 'layoutId'),
        detected: json['detected'] == true,
        running: json['running'] == true,
        foreground: json['foreground'] == true,
      );
}

class RemoteProfile {
  const RemoteProfile({
    required this.id,
    required this.name,
    required this.layoutId,
    this.platform,
    this.applicationId,
  });

  final String id;
  final String name;
  final String layoutId;
  final String? platform;
  final String? applicationId;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'layoutId': layoutId,
    'platform': platform,
    'applicationId': applicationId,
  };

  factory RemoteProfile.fromJson(Map<String, Object?> json) => RemoteProfile(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    layoutId: _requiredString(json, 'layoutId'),
    platform: _nullableString(json['platform']),
    applicationId: _nullableString(json['applicationId']),
  );
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

class DesktopManifest {
  const DesktopManifest({
    required this.revision,
    required this.currentProfileId,
    required this.settings,
    required this.layouts,
    required this.applications,
    required this.profiles,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final int revision;
  final String currentProfileId;
  final RemoteSettings settings;
  final List<RemoteShortcutLayout> layouts;
  final List<RemoteApplication> applications;
  final List<RemoteProfile> profiles;

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
  }) => DesktopManifest(
    schemaVersion: schemaVersion,
    revision: revision ?? this.revision,
    currentProfileId: currentProfileId ?? this.currentProfileId,
    settings: settings ?? this.settings,
    layouts: layouts ?? this.layouts,
    applications: applications ?? this.applications,
    profiles: profiles ?? this.profiles,
  );

  Map<String, Object?> toJson({bool forSync = false}) {
    final includeIcons = !forSync || settings.syncIcons;
    final syncedApplications = forSync
        ? settings.enableAppsSync
              ? applications
                    .where((application) => application.detected)
                    .toList(growable: false)
              : const <RemoteApplication>[]
        : applications;
    return {
      'schemaVersion': schemaVersion,
      'revision': revision,
      'currentProfileId': currentProfileId,
      'settings': settings.toJson(),
      'layouts': layouts
          .map((layout) => layout.toJson(includeIcons: includeIcons))
          .toList(growable: false),
      'applications': syncedApplications
          .map((app) => app.toJson(includeIcon: includeIcons))
          .toList(growable: false),
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
    };
  }

  factory DesktopManifest.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1) {
      throw const FormatException('Unsupported LumiaKeys manifest schema');
    }
    final manifest = DesktopManifest(
      schemaVersion: schemaVersion! as int,
      revision: json['revision'] is int ? json['revision']! as int : 1,
      currentProfileId: _requiredString(json, 'currentProfileId'),
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
    );
    manifest.validate();
    return manifest;
  }

  void validate() {
    if (layouts.isEmpty || profiles.isEmpty) {
      throw const FormatException('Manifest must contain layouts and profiles');
    }
    final layoutIds = layouts.map((layout) => layout.id).toSet();
    if (layoutIds.length != layouts.length ||
        profiles.any((profile) => !layoutIds.contains(profile.layoutId)) ||
        applications.any((app) => !layoutIds.contains(app.layoutId)) ||
        !profiles.any((profile) => profile.id == currentProfileId)) {
      throw const FormatException('Manifest contains invalid references');
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
        const RemoteShortcutButton(
          id: 'codex.open',
          name: 'Open Codex',
          icon: 'code',
          targetType: RemoteTargetType.launchApplication,
          target: 'codex',
          description: 'Bring Codex to the foreground',
        ),
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
      ],
      applications: const [
        RemoteApplication(
          id: 'codex',
          name: 'Codex / ChatGPT',
          icon: 'code',
          executable: 'Codex',
          layoutId: 'codex',
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
    final kind = RemoteActionKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => throw const FormatException('Unsupported remote action'),
    );
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
