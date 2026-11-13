library;

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
    this.computerId,
    this.schemaVersion = 1,
    this.applicationActivationSequence = 0,
    this.activatedApplicationId,
  });

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
    final syncedActivationApplicationId =
        activatedApplicationId != null &&
            syncedApplications.any((app) => app.id == activatedApplicationId)
        ? activatedApplicationId
        : null;
    return {
      'schemaVersion': schemaVersion,
      'revision': revision,
      'currentProfileId': currentProfileId,
      'computerId': computerId,
      'settings': settings.toJson(),
      'layouts': layouts
          .map((layout) => layout.toJson(includeIcons: includeIcons))
          .toList(growable: false),
      'applications': syncedApplications
          .map((app) => app.toJson(includeIcon: includeIcons))
          .toList(growable: false),
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
      'applicationActivationSequence': applicationActivationSequence,
      'activatedApplicationId': syncedActivationApplicationId,
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
      shortcut('chatgpt.startVoice', 'Start Voice Chat', 'mic', [
        'CTRL',
        'SHIFT',
        'V',
      ]),
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
