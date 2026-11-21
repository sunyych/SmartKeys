import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ChatGPT projection resolves platform defaults and filters unsupported rows',
    () {
      final chatGpt = DesktopManifest.starter().layoutById('chatgpt')!;
      final apple = projectChatGptLayout(chatGpt, RemoteShortcutPlatform.apple);
      final windows = projectChatGptLayout(
        chatGpt,
        RemoteShortcutPlatform.windows,
      );

      expect(
        apple.buttons
            .firstWhere((button) => button.id == 'chatgpt.chatView')
            .shortcut,
        ['CTRL', '1'],
      );
      expect(
        apple.buttons
            .firstWhere((button) => button.id == 'chatgpt.codexMode')
            .shortcut,
        ['CTRL', '3'],
      );
      expect(
        windows.buttons
            .firstWhere((button) => button.id == 'chatgpt.chatView')
            .shortcut,
        ['ALT', '1'],
      );
      expect(
        windows.buttons
            .firstWhere((button) => button.id == 'chatgpt.codexMode')
            .shortcut,
        ['ALT', '3'],
      );
      expect(
        apple.buttons.any((button) => button.id == 'chatgpt.startVoice'),
        isTrue,
      );
      final windowsVoice = windows.buttons.singleWhere(
        (button) => button.id == chatGptNativeVoiceShortcutId,
      );
      expect(windowsVoice.shortcut, isEmpty);
      expect(windowsVoice.enabled, isFalse);
      expect(
        apple.buttons.any((button) => button.id == 'chatgpt.codex.voice'),
        isFalse,
      );
      expect(
        windows.buttons.any((button) => button.id == 'chatgpt.codex.voice'),
        isFalse,
      );
      expect(
        apple.buttons.any((button) => button.id == 'chatgpt.codex.searchChats'),
        isFalse,
      );
      expect(
        windows.buttons.any(
          (button) => button.id == 'chatgpt.codex.searchChats',
        ),
        isFalse,
      );
      expect(
        DesktopManifest.starter().buttonById('chatgpt.startVoice'),
        isNotNull,
      );
    },
  );

  test('ChatGPT projection preserves custom bindings and resolves PRIMARY', () {
    final chatGpt = DesktopManifest.starter().layoutById('chatgpt')!;
    final custom = chatGpt.copyWith(
      buttons: chatGpt.buttons.map((button) {
        if (button.id == 'chatgpt.chatView') {
          return button.copyWith(shortcut: const ['PRIMARY', '3']);
        }
        if (button.id == 'chatgpt.codex.searchChats') {
          return button.copyWith(shortcut: const ['ALT', 'G']);
        }
        if (button.id == 'chatgpt.codex.previousChat') {
          return button.copyWith(shortcut: const ['ALT', 'LEFT']);
        }
        return button;
      }).toList(),
    );
    final windows = projectChatGptLayout(
      custom,
      RemoteShortcutPlatform.windows,
    );
    expect(
      windows.buttons
          .firstWhere((button) => button.id == 'chatgpt.chatView')
          .shortcut,
      ['CTRL', '3'],
    );
    expect(
      windows.buttons
          .firstWhere((button) => button.id == 'chatgpt.codex.searchChats')
          .shortcut,
      ['ALT', 'G'],
    );
    expect(
      windows.buttons
          .firstWhere((button) => button.id == 'chatgpt.codex.previousChat')
          .shortcut,
      ['ALT', 'LEFT'],
    );
  });

  test('Mac projection restores the middle row in saved legacy layouts', () {
    final starter = DesktopManifest.starter();
    final sourceLayout = starter.layoutById('chatgpt')!;
    final legacyLayout = sourceLayout.copyWith(
      buttons: [
        for (final button in sourceLayout.buttons)
          if (!{
            chatGptFastModeShortcutId,
            chatGptApproveShortcutId,
            chatGptDeclineShortcutId,
            chatGptBranchOffShortcutId,
          }.contains(button.id))
            button,
        sourceLayout.buttons
            .singleWhere((button) => button.id == chatGptApproveShortcutId)
            .copyWith(shortcut: const ['COMMAND', 'ENTER']),
      ],
    );
    final saved = DesktopManifest.fromJson(
      starter.copyWith(layouts: [
        for (final layout in starter.layouts)
          if (layout.id == 'chatgpt') legacyLayout else layout,
      ]).toJson(),
    );
    final legacy = saved.layoutById('chatgpt')!;
    final projections = [
      projectChatGptLayout(
        legacy,
        RemoteShortcutPlatform.apple,
        firstPageSize: regularShortcutCount,
      ),
      orderChatGptLayout(legacy, firstPageSize: regularShortcutCount),
    ];
    for (final projected in projections) {
      expect(
        projected.buttons.skip(4).take(4).map((button) => button.id),
        [
          chatGptFastModeShortcutId,
          chatGptApproveShortcutId,
          chatGptDeclineShortcutId,
          chatGptBranchOffShortcutId,
        ],
      );
      expect(projected.buttons[4].enabled, isFalse);
      expect(projected.buttons[4].shortcut, isEmpty);
      expect(projected.buttons[5].shortcut, ['COMMAND', 'ENTER']);
      expect(projected.buttons[6].shortcut, ['ESC']);
      expect(projected.buttons[7].enabled, isFalse);
      expect(projected.buttons[7].shortcut, isEmpty);
    }
  });

  test('PRIMARY resolver uses the native desktop modifier', () {
    expect(
      resolvePrimaryShortcut(const [
        'PRIMARY',
        'SHIFT',
        'N',
      ], RemoteShortcutPlatform.apple),
      ['COMMAND', 'SHIFT', 'N'],
    );
    expect(
      resolvePrimaryShortcut(const [
        'PRIMARY',
        'SHIFT',
        'N',
      ], RemoteShortcutPlatform.windows),
      ['CTRL', 'SHIFT', 'N'],
    );
  });

  test('Mac projection restores only stock Voice Mode bindings', () {
    const legacyStock = RemoteShortcutButton(
      id: chatGptNativeVoiceShortcutId,
      name: 'Start Voice Chat',
      icon: '',
      targetType: RemoteTargetType.keyboardShortcut,
      description: 'CTRL + SHIFT + V',
      enabled: false,
    );
    final restored = projectChatGptNativeVoice(
      legacyStock,
      RemoteShortcutPlatform.apple,
    );
    expect(restored.shortcut, ['CTRL', 'SHIFT', 'V']);
    expect(restored.enabled, isTrue);

    final deliberate = projectChatGptNativeVoice(
      saveExplicitChatGptVoiceBinding(
        legacyStock,
        RemoteShortcutPlatform.apple,
      ),
      RemoteShortcutPlatform.apple,
    );
    expect(deliberate.shortcut, isEmpty);
    expect(deliberate.enabled, isFalse);
  });

  test('Mac Dictate reuses the phone Dictation cell with capability gating', () {
    final chatGpt = DesktopManifest.regularStarter().layoutById('chatgpt')!;
    final apple = projectChatGptSystemDictation(
      chatGpt,
      platform: RemoteShortcutPlatform.apple,
      supported: true,
    );
    final dictate = apple.buttons.singleWhere(
      (button) => button.id == chatGptSystemDictationShortcutId,
    );
    expect(dictate.name, 'Dictate');
    expect(dictate.targetType, RemoteTargetType.system);
    expect(dictate.target, 'lumiakeySystemDictation');
    expect(dictate.enabled, isTrue);
    expect(apple.buttons.any(isChatGptLocalDictationShortcut), isFalse);

    final setup = projectChatGptSystemDictation(
      chatGpt,
      platform: RemoteShortcutPlatform.apple,
      supported: false,
    );
    final unavailable = setup.buttons.singleWhere(
      (button) => button.id == chatGptSystemDictationShortcutId,
    );
    expect(unavailable.name, 'Dictate');
    expect(unavailable.enabled, isFalse);

    final windows = projectChatGptSystemDictation(
      chatGpt,
      platform: RemoteShortcutPlatform.windows,
      supported: false,
    );
    expect(
      windows.buttons.any(isChatGptLocalDictationShortcut),
      isTrue,
    );
    expect(
      windows.buttons.any((button) => button.id == chatGptSystemDictationShortcutId),
      isFalse,
    );
  });

  test('ChatGPT fixed order puts everyday actions first and Review second', () {
    final starter = DesktopManifest.starter().layoutById('chatgpt')!;
    expect(chatGptShortcutsPerPage, 15);
    expect(chatGptPrimaryShortcutIds, hasLength(chatGptShortcutsPerPage));

    for (final platform in [
      RemoteShortcutPlatform.apple,
      RemoteShortcutPlatform.windows,
    ]) {
      final projected = projectChatGptLayout(starter, platform);
      final ids = projected.buttons.map((button) => button.id).toList();
      expect(
        ids.take(chatGptShortcutsPerPage).toList(),
        chatGptPrimaryShortcutIds,
      );
      expect(ids[chatGptShortcutsPerPage], 'chatgpt.codex.review');
      expect(ids.indexOf('chatgpt.codex.send'), lessThan(3));
      expect(ids.indexOf('chatgpt.codex.copy'), lessThan(4));
      expect(ids.indexOf('chatgpt.codex.paste'), lessThan(5));
    }
  });

  test(
    'ChatGPT order is stable and keeps imported custom button properties',
    () {
      final starter = DesktopManifest.starter().layoutById('chatgpt')!;
      const customButton = RemoteShortcutButton(
        id: 'chatgpt.custom.extra',
        name: 'Custom Action',
        icon: 'star',
        targetType: RemoteTargetType.keyboardShortcut,
        shortcut: ['ALT', 'Z'],
        description: 'Imported custom action',
        enabled: false,
      );
      final firstInput = starter.copyWith(
        buttons: [...starter.buttons, customButton],
      );
      final secondInput = starter.copyWith(
        buttons: [...starter.buttons.reversed, customButton],
      );
      final first = orderChatGptLayout(firstInput);
      final second = orderChatGptLayout(secondInput);
      expect(
        first.buttons.map((button) => button.id).toList(),
        second.buttons.map((button) => button.id).toList(),
      );
      final restored = first.buttons.firstWhere(
        (button) => button.id == customButton.id,
      );
      expect(restored.shortcut, ['ALT', 'Z']);
      expect(restored.description, 'Imported custom action');
      expect(restored.enabled, isFalse);
      expect(
        first.buttons.indexWhere(
          (button) => button.id == 'chatgpt.codex.review',
        ),
        chatGptShortcutsPerPage,
      );
    },
  );

  test(
    'projection omits unsupported OS actions without exporting them away',
    () {
      final starter = DesktopManifest.starter();
      final chatGpt = starter.layoutById('chatgpt')!;
      final custom = chatGpt.copyWith(
        buttons: chatGpt.buttons.map((button) {
          if (button.id == 'chatgpt.find') {
            return button.copyWith(shortcut: const ['COMMAND', 'F']);
          }
          return button;
        }).toList(),
      );
      expect(
        projectChatGptLayout(
          custom,
          RemoteShortcutPlatform.windows,
        ).buttons.any((button) => button.id == 'chatgpt.find'),
        isFalse,
      );
      expect(
        projectChatGptLayout(
          chatGpt,
          RemoteShortcutPlatform.other,
        ).buttons.any((button) => button.targetType == RemoteTargetType.system),
        isFalse,
      );
      expect(starter.buttonById('chatgpt.codex.screenshot'), isNotNull);
    },
  );

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
    expect(restored.applicationById('codex'), isNull);
    expect(restored.applicationById('chatgpt')!.name, 'ChatGPT');
    expect(restored.applicationById('chatgpt')!.layoutId, 'chatgpt');
    expect(restored.buttonById('chatgpt.chatView')!.shortcut, ['ALT', '1']);
    expect(restored.buttonById('chatgpt.newChat')!.shortcut, ['PRIMARY', 'N']);
    expect(restored.buttonById('chatgpt.codexMode')!.shortcut, ['ALT', '3']);
    expect(
      restored
          .layoutById('chatgpt')!
          .buttons
          .take(2)
          .map((button) => button.id),
      ['chatgpt.chatView', 'chatgpt.codexMode'],
    );
    final chatGptButtons = restored.layoutById('chatgpt')!.buttons;
    expect(
      chatGptButtons
          .where((button) => button.name == 'New Chat')
          .map((b) => b.id),
      ['chatgpt.newChat'],
    );
    expect(restored.buttonById('chatgpt.codex.newChat'), isNull);
    expect(restored.buttonById('chatgpt.codex.sidebar'), isNull);
    expect(restored.buttonById('chatgpt.sidebar')!.shortcut, ['PRIMARY', 'B']);
    expect(restored.buttonById('chatgpt.codex.project'), isNotNull);
    expect(restored.buttonById('chatgpt.codex.alternateSend'), isNotNull);
    expect(restored.buttonById('chatgpt.codex.screenshot'), isNotNull);
    final shortcutsByChord = <String, Set<String>>{};
    for (final button in chatGptButtons.where(
      (button) =>
          button.targetType == RemoteTargetType.keyboardShortcut &&
          button.shortcut.isNotEmpty,
    )) {
      shortcutsByChord
          .putIfAbsent(button.shortcut.join('+'), () => {})
          .add(button.id);
    }
    expect(
      {
        for (final entry in shortcutsByChord.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      },
      {
        'ENTER': {'chatgpt.codex.send', chatGptApproveShortcutId},
        'ESC': {'chatgpt.codex.focusInput', chatGptDeclineShortcutId},
      },
    );
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
    expect(manifest.applicationById('codex'), isNull);
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
                .map((app) => app.copyWith(detected: app.id == 'chatgpt'))
                .toList(),
          )
          .toJson(forSync: true),
    );
    expect(synced.layoutById('vibe.claude'), isNotNull);
    expect(synced.applicationById('claude'), isNull);
  });

  test('browser and meeting apps ship with stable keyboard-only layouts', () {
    final manifest = DesktopManifest.starter();
    for (final app in const [
      'chrome',
      'edge',
      'firefox',
      'safari',
      'teams',
      'zoom',
    ]) {
      final application = manifest.applicationById(app)!;
      expect(manifest.layoutById(application.layoutId), isNotNull);
      expect(manifest.layoutById(application.layoutId)!.buttons, isNotEmpty);
      expect(
        manifest
            .layoutById(application.layoutId)!
            .buttons
            .every(
              (button) =>
                  button.targetType == RemoteTargetType.keyboardShortcut ||
                  (app == 'chrome' &&
                      button.targetType == RemoteTargetType.openUrl),
            ),
        isTrue,
      );
    }
    expect(manifest.buttonById('teams.mute')!.shortcut, [
      'PRIMARY',
      'SHIFT',
      'M',
    ]);
    expect(manifest.buttonById('teams.video')!.shortcut, [
      'PRIMARY',
      'SHIFT',
      'O',
    ]);
    expect(manifest.buttonById('teams.hand')!.shortcut, [
      'PRIMARY',
      'SHIFT',
      'K',
    ]);
    expect(manifest.buttonById('zoom.mute')!.shortcut, ['ALT', 'A']);
    expect(manifest.buttonById('zoom.video')!.shortcut, ['ALT', 'V']);
    expect(manifest.buttonById('zoom.hand')!.shortcut, ['ALT', 'Y']);
    expect(manifest.applicationById('edge')!.name, 'Microsoft Edge');
    expect(manifest.buttonById('edge.newTab')!.shortcut, ['PRIMARY', 'T']);
  });

  test(
    'computer identity stays optional for old manifests and syncs when set',
    () {
      final legacy = DesktopManifest.starter().toJson()..remove('computerId');
      final restoredLegacy = DesktopManifest.fromJson(legacy);
      expect(restoredLegacy.computerId, isNull);

      final identified = restoredLegacy.copyWith(computerId: 'a' * 32);
      final synced = DesktopManifest.fromJson(identified.toJson(forSync: true));
      expect(synced.computerId, 'a' * 32);
    },
  );

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
              detected: application.id == 'chatgpt',
              running: application.id == 'chatgpt',
            ),
          )
          .toList(growable: false),
    );

    final synced = DesktopManifest.fromJson(detected.toJson(forSync: true));
    expect(synced.applications.single.id, 'chatgpt');
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

  test(
    'launcher slots round trip, default for legacy manifests, and sync only assigned apps',
    () {
      final starter = DesktopManifest.starter();
      final applications = starter.applications
          .map((app) => app.copyWith(detected: false))
          .toList(growable: false);
      final configured = starter.copyWith(
        applications: applications,
        launcherApplicationIds: const [
          'chrome',
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
      );
      final synced = DesktopManifest.fromJson(configured.toJson(forSync: true));
      expect(synced.launcherApplicationIds.first, 'chrome');
      expect(synced.applicationById('chrome')?.detected, isFalse);

      final legacyJson = starter.toJson()..remove('launcherApplicationIds');
      expect(
        DesktopManifest.fromJson(legacyJson).launcherApplicationIds,
        List<String?>.filled(launcherSlotCount, null),
      );
      final malformed = starter.toJson()
        ..['launcherApplicationIds'] = ['chrome'];
      expect(() => DesktopManifest.fromJson(malformed), throwsFormatException);

      final hidden = configured.copyWith(
        settings: configured.settings.copyWith(enableAppsSync: false),
      );
      final hiddenSync = hidden.toJson(forSync: true);
      expect(
        hiddenSync['launcherApplicationIds'],
        List<String?>.filled(launcherSlotCount, null),
      );
      expect(hiddenSync['applications'], isEmpty);
    },
  );
}
