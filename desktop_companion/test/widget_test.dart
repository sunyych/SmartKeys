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
            detected: app.id == 'vscode' || app.id == 'codex',
            running: app.id == 'vscode',
            foreground: app.id == 'vscode',
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

class _RecordingMacSystemControl implements MacSystemControl {
  final List<bool> values = [];

  @override
  Future<void> setDark(bool enabled) async => values.add(enabled);
}

void main() {
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
      expect(call.$2.last, '%{LEFT}');
    } else {
      expect(call.$1, 'xdotool');
      expect(call.$2, ['key', 'ALT+LEFT']);
    }
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
            buttons: const [
              RemoteShortcutButton(
                id: 'codex.accept',
                name: 'Accept',
                icon: 'check',
                targetType: RemoteTargetType.keyboardShortcut,
                shortcut: ['TAB'],
              ),
            ],
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
        layouts: starter.layouts
            .map(
              (layout) => switch (layout.id) {
                'codex' => legacyCodex,
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
      expect(controller.manifest.buttonById('codex.open'), isNotNull);
      expect(controller.manifest.buttonById('codex.voice'), isNotNull);
      expect(controller.manifest.buttonById('codex.send'), isNotNull);
      expect(controller.manifest.buttonById('codex.accept'), isNull);
      expect(
        controller.manifest.applicationById('codex')!.name,
        'Codex / ChatGPT',
      );
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
          'codex.open',
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
        'codex',
      });
      expect(synced.applicationById('vscode')!.foreground, isTrue);
    },
  );

  testWidgets('shows the desktop settings navigation', (tester) async {
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
    expect(find.text('Desktop offline'), findsOneWidget);
    expect(find.text('Waiting for phone'), findsOneWidget);
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
