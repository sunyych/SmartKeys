import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/main.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _InstalledDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async {
    return apps
        .map(
          (app) => app.copyWith(
            detected: app.id == 'vscode' || app.id == 'chatgpt',
            running: app.id == 'vscode',
            foreground: app.id == 'vscode',
          ),
        )
        .toList(growable: false);
  }
}

class _SequencedDiscovery implements ApplicationDiscovery {
  final foregrounds = <String?>[null, 'finder', 'finder', 'appleMusic'];
  int index = 0;

  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async {
    final foreground = foregrounds[index.clamp(0, foregrounds.length - 1)];
    index++;
    return apps
        .map(
          (app) => app.copyWith(
            detected: app.id == 'finder' || app.id == 'appleMusic',
            running: app.id == foreground,
            foreground: app.id == foreground,
          ),
        )
        .toList(growable: false);
  }
}

class _RecordingRunner implements DesktopProcessRunner {
  final List<(String, List<String>)> calls = [];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    return ProcessResult(1, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      throw UnsupportedError('The dark action only uses run');
}

class _SuccessfulRecordingRunner implements DesktopProcessRunner {
  final List<(String, List<String>)> calls = [];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    return ProcessResult(0, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      throw UnsupportedError('This test only uses run');
}

class _FocusedRecordingRunner extends _SuccessfulRecordingRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    if (Platform.isMacOS && executable == '/usr/bin/osascript') {
      return ProcessResult(0, 0, 'Code', '');
    }
    return ProcessResult(0, 0, 'FOCUSED', '');
  }
}

class _EdgeStartRunner implements DesktopProcessRunner {
  final starts = <(String, List<String>)>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async =>
      ProcessResult(0, 0, '', '');

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    starts.add((executable, arguments));
    throw UnsupportedError('The test records the selected browser executable.');
  }
}

class _EdgeForegroundRunner extends _SuccessfulRecordingRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    if (Platform.isMacOS && executable == '/usr/bin/osascript') {
      return ProcessResult(0, 0, 'Microsoft Edge', '');
    }
    if (Platform.isLinux && executable == 'xdotool') {
      return ProcessResult(0, 0, '123', '');
    }
    if (Platform.isLinux && executable == 'ps') {
      return ProcessResult(0, 0, 'microsoft-edge-stable', '');
    }
    return ProcessResult(0, 0, '', '');
  }
}

class _RecordingMacSystemControl implements MacSystemControl {
  final List<bool> values = [];

  @override
  Future<void> setDark(bool enabled) async => values.add(enabled);
}

void main() {
  test(
    'ChatGPT and legacy Codex activation preserve the current view',
    () async {
      if (!Platform.isWindows) return;
      final chatGptRunner = _FocusedRecordingRunner();
      await DesktopActions(runner: chatGptRunner).activateApplication(
        const RemoteApplication(
          id: 'chatgpt',
          name: 'ChatGPT',
          icon: 'chat',
          executable: 'ChatGPT',
          layoutId: 'chatgpt',
        ),
      );
      expect(chatGptRunner.calls, hasLength(1));
      expect(chatGptRunner.calls.first.$2[6], "'ChatGPT'");
      final activationScript = chatGptRunner.calls.first.$2[3];
      expect(activationScript, contains('GetForegroundWindow'));
      expect(activationScript, contains('GetAsyncKeyState'));
      expect(activationScript, contains('ShowWindowAsync'));
      expect(activationScript, contains('FindMainWindows'));
      expect(activationScript, contains('WS_EX_TOOLWINDOW'));
      expect(activationScript, contains('WS_EX_NOACTIVATE'));
      expect(activationScript, contains('AppWindow'));
      expect(activationScript, contains(r"$processNames -contains 'ChatGPT'"));
      expect(
        activationScript,
        contains('did not activate the selected app window'),
      );

      final codexRunner = _FocusedRecordingRunner();
      await DesktopActions(runner: codexRunner).activateApplication(
        const RemoteApplication(
          id: 'codex',
          name: 'Codex / ChatGPT',
          icon: 'code',
          executable: 'ChatGPT',
          layoutId: 'codex',
        ),
      );
      expect(codexRunner.calls, hasLength(1));
    },
  );

  test('launches Microsoft Edge through the native app entry', () async {
    final app = RemoteApplication(
      id: 'edge',
      name: 'Microsoft Edge',
      icon: 'language',
      executable: 'microsoft-edge',
      layoutId: 'app.edge',
      detected: true,
    );

    if (Platform.isMacOS) {
      final runner = _EdgeForegroundRunner();
      await DesktopActions(runner: runner).activateApplication(app);
      expect(runner.calls.first, ('/usr/bin/open', ['-a', 'Microsoft Edge']));
    } else if (Platform.isWindows) {
      final runner = _SuccessfulRecordingRunner();
      await DesktopActions(runner: runner).activateApplication(app);
      expect(runner.calls.single.$1, 'powershell.exe');
      expect(runner.calls.single.$2[4], "'msedge'");
      expect(runner.calls.single.$2[5], "'msedge.exe'");
      expect(runner.calls.single.$2[6], "'Microsoft Edge'");
      expect(runner.calls.single.$2[3], contains('Get-StartApps'));
    } else {
      final runner = _EdgeStartRunner();
      await expectLater(
        DesktopActions(runner: runner).activateApplication(app),
        throwsUnsupportedError,
      );
      expect(runner.starts, [('microsoft-edge', const <String>[])]);
    }
  });

  test(
    'starter app activation reuses and verifies its desktop window',
    () async {
      final runner = _FocusedRecordingRunner();
      await DesktopActions(runner: runner).activateApplication(
        const RemoteApplication(
          id: 'vscode',
          name: 'VSCode',
          icon: 'code',
          executable: 'Visual Studio Code',
          layoutId: 'app.vscode',
        ),
      );
      if (Platform.isWindows) {
        final script = runner.calls.single.$2[3];
        expect(script, contains('Get-StartApps'));
        expect(script, contains('ShowWindowAsync'));
        expect(script, contains('GetForegroundWindow'));
        expect(script, contains('refusing to report activation success'));
        expect(runner.calls.single.$2[4], "'Code'");
        expect(runner.calls.single.$2[5], "'Code.exe'");
        expect(runner.calls.single.$2[6], contains('Visual Studio Code'));
      } else if (Platform.isMacOS) {
        expect(runner.calls.first, (
          '/usr/bin/open',
          ['-a', 'Visual Studio Code'],
        ));
      }
    },
  );

  test('Edge browser shortcut checks its matching foreground app', () async {
    final runner = _EdgeForegroundRunner();
    await DesktopActions(
      runner: runner,
    ).sendShortcut(const ['CTRL', 'R'], expectedAppId: 'edge');

    final script = Platform.isWindows
        ? runner.calls.single.$2[3]
        : runner.calls.last.$2.last;
    if (Platform.isMacOS) {
      expect(script, contains('Microsoft Edge'));
    } else if (Platform.isWindows) {
      expect(runner.calls.single.$2[4], contains('msedge'));
    } else {
      expect(runner.calls.first.$2, ['getactivewindow', 'getwindowpid']);
      expect(runner.calls.last.$2, ['key', 'CTRL+R']);
    }
  });

  test('quotes generic Windows app launch arguments', () async {
    if (!Platform.isWindows) return;
    final runner = _SuccessfulRecordingRunner();
    await DesktopActions(
      runner: runner,
    ).launchApplication('Visual Studio Code');
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.$1, 'powershell.exe');
    expect(
      runner.calls.single.$2[3],
      r'& { Start-Process -FilePath $args[0] }',
    );
    expect(runner.calls.single.$2[4], "'Code.exe'");
  });

  test('rejects unknown desktop action kinds', () async {
    await expectLater(
      DesktopActions().executeLegacy({'kind': 'shell', 'command': 'anything'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects shortcut keys outside the allowlist', () async {
    await expectLater(
      DesktopActions().executeLegacy({
        'kind': 'shortcut',
        'keys': ['CTRL', 'NOT_A_REAL_KEY'],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('resolves browser navigation to the host shortcut', () async {
    final runner = _RecordingRunner();
    final actions = DesktopActions(runner: runner);

    await actions.sendShortcut(const ['BROWSER_BACK']);

    expect(runner.calls, hasLength(1));
    final call = runner.calls.single;
    if (Platform.isMacOS) {
      expect(call.$1, '/usr/bin/osascript');
      expect(call.$2.join(' '), contains('command down'));
      expect(call.$2.join(' '), contains('['));
    } else if (Platform.isWindows) {
      expect(call.$1, 'powershell.exe');
      expect(call.$2[3], contains(r'param($approvedProcesses, $keyStroke)'));
      expect(
        call.$2[3],
        contains(r'[System.Windows.Forms.SendKeys]::SendWait($keyStroke)'),
      );
      expect(call.$2.last, "'%{LEFT}'");
    } else {
      expect(call.$1, 'xdotool');
      expect(call.$2, ['key', 'ALT+LEFT']);
    }
  });

  test('ChatGPT key guard rejects pet overlay windows on Windows', () async {
    if (!Platform.isWindows) return;
    final runner = _RecordingRunner();
    await DesktopActions(
      runner: runner,
    ).sendShortcut(const ['PRIMARY', 'N'], expectedAppId: 'chatgpt');
    final script = runner.calls.single.$2[3];
    expect(script, contains('WS_EX_TOOLWINDOW'));
    expect(script, contains('WS_EX_NOACTIVATE'));
    expect(script, contains(r'GetWindow($foregroundHandle, 4)'));
    expect(script, contains('Switch to the main ChatGPT window'));
  });

  test(
    'accepts the fixed dark action without arbitrary command input',
    () async {
      final runner = _RecordingRunner();
      final macSystemControl = _RecordingMacSystemControl();
      final actions = DesktopActions(
        runner: runner,
        macSystemControl: macSystemControl,
      );

      await actions.executeLegacy({
        'kind': 'dark',
        'enabled': true,
        'command': 'ignored',
      });
      await actions.executeLegacy({'kind': 'dark', 'enabled': false});

      if (Platform.isMacOS) {
        expect(macSystemControl.values, [true, false]);
        expect(runner.calls, isEmpty);
      } else if (Platform.isWindows) {
        expect(runner.calls, hasLength(3));
        expect(
          runner.calls.every((call) => call.$1 == 'powershell.exe'),
          isTrue,
        );
      } else {
        expect(runner.calls, hasLength(2));
        expect(
          runner.calls.every((call) => call.$1 == 'brightnessctl'),
          isTrue,
        );
      }
    },
  );

  test(
    'upgrades legacy app profiles and publishes installed runtime state',
    () async {
      final starter = DesktopManifest.starter();
      final legacyCodex = starter
          .layoutById('codex')!
          .copyWith(
            buttons: starter
                .layoutById('codex')!
                .buttons
                .map(
                  (button) => button.id == 'codex.openFolder'
                      ? button.copyWith(
                          shortcut: const ['PRIMARY', 'SHIFT', 'O'],
                        )
                      : button.id == 'codex.sidebar'
                      ? button.copyWith(
                          shortcut: const ['PRIMARY', 'SHIFT', 'B'],
                        )
                      : button,
                )
                .toList(growable: false),
          );
      final legacyChatGpt = starter
          .layoutById('chatgpt')!
          .copyWith(
            buttons: [
              ...starter
                  .layoutById('chatgpt')!
                  .buttons
                  .where(
                    (button) => const {
                      'chatgpt.chatView',
                      'chatgpt.startVoice',
                      'chatgpt.newChat',
                      'chatgpt.previousChat',
                      'chatgpt.nextChat',
                      'chatgpt.find',
                      'chatgpt.sidebar',
                    }.contains(button.id),
                  )
                  .map(
                    (button) => button.id == 'chatgpt.newChat'
                        ? button.copyWith(
                            shortcut: const ['CTRL', 'SHIFT', 'N'],
                          )
                        : button,
                  ),
              const RemoteShortcutButton(
                id: 'chatgpt.codex.sidebar',
                name: 'Show / Hide Sidebar',
                icon: 'menu_open',
                targetType: RemoteTargetType.keyboardShortcut,
                shortcut: ['PRIMARY', 'B'],
              ),
            ],
          );
      final legacyVibeCodex = starter
          .layoutById('vibe.codex')!
          .copyWith(
            buttons: starter
                .layoutById('vibe.codex')!
                .buttons
                .map(
                  (button) => button.id == 'vibe.codex.alternateSend'
                      ? button.copyWith(
                          shortcut: const ['PRIMARY', 'SHIFT', 'ENTER'],
                        )
                      : button,
                )
                .toList(growable: false),
          );
      final legacyChrome = starter
          .layoutById('app.chrome')!
          .copyWith(
            buttons: starter
                .layoutById('app.chrome')!
                .buttons
                .where(
                  (button) =>
                      button.id == 'chrome.newTab' ||
                      button.id == 'chrome.closeTab',
                )
                .toList(growable: false),
          );
      final legacy = starter.copyWith(
        applications: [
          ...starter.applications,
          const RemoteApplication(
            id: 'codex',
            name: 'Codex / ChatGPT',
            icon: 'code',
            executable: 'ChatGPT',
            layoutId: 'codex',
            detected: true,
            running: true,
          ),
        ],
        activatedApplicationId: 'codex',
        layouts: starter.layouts
            .map(
              (layout) => switch (layout.id) {
                'codex' => legacyCodex,
                'chatgpt' => legacyChatGpt,
                'vibe.codex' => legacyVibeCodex,
                'app.chrome' => legacyChrome,
                _ => layout,
              },
            )
            .toList(growable: false),
        profiles: const [
          RemoteProfile(id: 'default', name: 'Default', layoutId: 'keyboard'),
          RemoteProfile(
            id: 'windows',
            name: 'Windows',
            layoutId: 'keyboard',
            platform: 'windows',
          ),
          RemoteProfile(
            id: 'vscode',
            name: 'VSCode',
            layoutId: 'app.vscode',
            applicationId: 'vscode',
          ),
        ],
      );
      final store = MemoryDesktopConfigStore()..value = legacy;
      final controller = DesktopController(
        store: store,
        discovery: _InstalledDiscovery(),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.manifest.profiles.map((profile) => profile.id), [
        'default',
      ]);
      expect(controller.manifest.buttonById('codex.open'), isNull);
      expect(controller.manifest.buttonById('codex.focusInput'), isNotNull);
      expect(controller.manifest.buttonById('codex.voice'), isNotNull);
      expect(controller.manifest.buttonById('codex.send'), isNotNull);
      expect(controller.manifest.buttonById('codex.accept'), isNull);
      expect(controller.manifest.buttonById('chatgpt.newChat')!.shortcut, [
        'CTRL',
        'SHIFT',
        'N',
      ]);
      expect(
        controller.manifest.buttonById('chatgpt.codex.openFolder')!.shortcut,
        Platform.isMacOS ? ['COMMAND', 'SHIFT', 'O'] : ['CTRL', 'SHIFT', 'O'],
      );
      expect(
        controller.manifest.buttonById('chatgpt.sidebar')!.shortcut,
        Platform.isMacOS ? ['COMMAND', 'SHIFT', 'B'] : ['CTRL', 'SHIFT', 'B'],
      );
      expect(controller.manifest.buttonById('chatgpt.codex.sidebar'), isNull);
      expect(
        controller.manifest.buttonById('chatgpt.codex.alternateSend')!.shortcut,
        Platform.isMacOS
            ? ['COMMAND', 'SHIFT', 'ENTER']
            : ['CTRL', 'SHIFT', 'ENTER'],
      );
      expect(
        controller.manifestForExport
            .buttonById('chatgpt.codex.openFolder')!
            .shortcut,
        ['PRIMARY', 'SHIFT', 'O'],
      );
      expect(controller.manifest.applicationById('codex'), isNull);
      expect(controller.manifest.applicationById('chatgpt')!.detected, isTrue);
      expect(controller.manifest.activatedApplicationId, 'vscode');
      expect(
        controller.manifest.layoutById('app.chrome')!.buttons,
        hasLength(15),
      );
      expect(
        controller.manifest.buttonById('chrome.passwordManager'),
        isNotNull,
      );
      expect(controller.manifest.buttonById('chrome.mute'), isNotNull);
      expect(
        controller.manifest
            .layoutById('codex')!
            .buttons
            .take(6)
            .map((button) => button.id),
        [
          'codex.focusInput',
          'codex.voice',
          'codex.newChat',
          'codex.previousConversation',
          'codex.nextConversation',
          'codex.send',
        ],
      );
      expect(controller.manifest.applicationById('vscode')!.running, isTrue);
      expect(controller.manifest.applicationById('vscode')!.foreground, isTrue);
      final synced = DesktopManifest.fromJson(
        controller.manifest.toJson(forSync: true),
      );
      expect(synced.applications.map((app) => app.id).toSet(), {
        'vscode',
        'chatgpt',
      });
      expect(synced.applicationById('vscode')!.foreground, isTrue);
      final migratedButtonIds = controller.manifest
          .layoutById('chatgpt')!
          .buttons
          .map((button) => button.id)
          .toList(growable: false);
      expect(migratedButtonIds.toSet(), hasLength(migratedButtonIds.length));
      final reopened = DesktopController(
        store: store,
        discovery: _NoopDiscovery(),
      );
      addTearDown(reopened.dispose);
      await reopened.initialize();
      final reopenedButtons = reopened.manifest
          .layoutById('chatgpt')!
          .buttons
          .map((button) => button.id)
          .toList(growable: false);
      expect(reopenedButtons.toSet(), hasLength(reopenedButtons.length));
      expect(
        reopened.manifest.buttonById('chatgpt.codex.alternateSend'),
        isNotNull,
      );
    },
  );

  test('publishes one activation sequence per foreground app change', () async {
    final discovery = _SequencedDiscovery();
    final controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      discovery: discovery,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.manifest.applicationActivationSequence, 0);

    await controller.refreshApplications();
    expect(controller.manifest.applicationActivationSequence, 1);
    expect(controller.manifest.activatedApplicationId, 'finder');

    await controller.refreshApplications();
    expect(controller.manifest.applicationActivationSequence, 1);

    await controller.refreshApplications();
    expect(controller.manifest.applicationActivationSequence, 2);
    expect(controller.manifest.activatedApplicationId, 'appleMusic');
  });

  testWidgets('shows the desktop settings navigation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      discovery: _NoopDiscovery(),
    );
    await controller.initialize();
    await tester.pumpWidget(
      CompanionApp(controller: controller, startServer: false),
    );
    await tester.pump();

    expect(find.text('General'), findsWidgets);
    expect(find.text('Shortcut Layout'), findsOneWidget);
    expect(find.text('Enable Apps Sync'), findsOneWidget);
    expect(find.text('Current Shortcut Profile'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-status-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-brand-logo')), findsOneWidget);
    final navigationLogo = tester.widget<Image>(
      find.byKey(const ValueKey('desktop-brand-logo-image')),
    );
    expect((navigationLogo.image as AssetImage).assetName, desktopBrandAsset);
    expect(find.byIcon(Icons.keyboard_command_key), findsNothing);
    expect(find.text('Desktop offline'), findsOneWidget);
    expect(find.text('Waiting for phone'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pump();
    expect(find.text('LumiaKey'), findsNWidgets(2));
    final aboutLogo = tester.widget<Image>(
      find.byKey(const ValueKey('desktop-about-logo-image')),
    );
    expect((aboutLogo.image as AssetImage).assetName, desktopBrandAsset);
    expect(find.byIcon(Icons.keyboard_command_key), findsNothing);
  });

  testWidgets('shortcut layout editor persists desktop-owned changes', (
    tester,
  ) async {
    final store = MemoryDesktopConfigStore();
    final controller = DesktopController(
      store: store,
      discovery: _NoopDiscovery(),
    );
    await controller.initialize();
    await tester.pumpWidget(
      CompanionApp(controller: controller, startServer: false),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('desktop-button-keyboard.copy')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('shortcut-field')),
      'PRIMARY + SHIFT + C',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(controller.manifest.buttonById('keyboard.copy')!.shortcut, [
      'PRIMARY',
      'SHIFT',
      'C',
    ]);
    expect(store.saveCount, greaterThan(1));
  });
}
