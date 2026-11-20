import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/shortcut_transfer_service.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _RecordingActions extends DesktopActions {
  final executed = <String>[];
  final activated = <String>[];

  @override
  Future<void> executeButton(
    RemoteShortcutButton button,
    DesktopManifest manifest, {
    String? expectedAppId,
  }) async {
    executed.add('${button.id}:$expectedAppId');
  }

  @override
  Future<void> activateApplication(RemoteApplication app) async {
    activated.add(app.id);
  }
}

class _ProcessRunner implements DesktopProcessRunner {
  final calls = <(String, List<String>)>[];
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    return ProcessResult(0, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      throw UnimplementedError();
}

void main() {
  test(
    'Vibe shortcuts require live matching foreground and pass target guard',
    () async {
      final actions = _RecordingActions();
      var foreground = false;
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        actions: actions,
        discovery: _NoopDiscovery(),
        foregroundProbe: (_) async => foreground,
      );
      await controller.initialize();

      await expectLater(
        controller.executeRemote(
          const RemoteActionRequest.button('vibe.cursor.newChat'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(actions.executed, isEmpty);

      foreground = true;
      await controller.executeRemote(
        const RemoteActionRequest.button('vibe.cursor.newChat'),
      );
      expect(actions.executed, ['vibe.cursor.newChat:cursor']);
      controller.dispose();
    },
  );

  test('Vibe app requests activate only manifest-owned app IDs', () async {
    final actions = _RecordingActions();
    final starter = DesktopManifest.starter();
    final controller = DesktopController(
      store: MemoryDesktopConfigStore()
        ..value = starter.copyWith(
          applications: starter.applications
              .map((app) => app.copyWith(detected: app.id == 'claude'))
              .toList(growable: false),
        ),
      actions: actions,
      discovery: _NoopDiscovery(),
    );
    await controller.initialize();
    await controller.executeRemote(
      const RemoteActionRequest.launchApplication('claude'),
    );
    expect(actions.activated, ['claude']);
    await expectLater(
      controller.executeRemote(
        const RemoteActionRequest.launchApplication('../bad'),
      ),
      throwsA(isA<FormatException>()),
    );
    controller.dispose();
  });

  test(
    'manifest upgrade preserves saved legacy and Vibe shortcut edits',
    () async {
      final initial = DesktopManifest.starter();
      final codexLegacy = initial.layoutById('codex')!;
      final vibeCodex = initial.layoutById('vibe.codex')!;
      final customized = initial.copyWith(
        layouts: initial.layouts.map((layout) {
          if (layout.id == 'codex') {
            return layout.copyWith(
              buttons: layout.buttons
                  .map(
                    (button) => button.id == 'codex.newChat'
                        ? button.copyWith(
                            shortcut: const ['PRIMARY', 'SHIFT', 'N'],
                          )
                        : button,
                  )
                  .toList(),
            );
          }
          if (layout.id == 'vibe.codex') {
            return layout.copyWith(
              buttons: layout.buttons
                  .map(
                    (button) => button.id == 'vibe.codex.project'
                        ? button.copyWith(
                            shortcut: const ['PRIMARY', 'ALT', 'O'],
                          )
                        : button,
                  )
                  .toList(),
            );
          }
          return layout;
        }).toList(),
      );
      expect(codexLegacy.id, 'codex');
      expect(vibeCodex.id, 'vibe.codex');
      final store = MemoryDesktopConfigStore()..value = customized;
      final controller = DesktopController(
        store: store,
        discovery: _NoopDiscovery(),
        actions: _RecordingActions(),
      );
      await controller.initialize();
      expect(controller.manifest.layoutById('codex'), isNull);
      expect(controller.manifest.layoutById('vibe.codex'), isNull);
      expect(
        controller.manifestForExport.buttonById('chatgpt.newChat')!.shortcut,
        ['PRIMARY', 'SHIFT', 'N'],
      );
      expect(
        controller.manifestForExport
            .buttonById('chatgpt.codex.project')!
            .shortcut,
        ['PRIMARY', 'ALT', 'O'],
      );
      controller.dispose();
    },
  );

  test(
    'Micro requests are bound, confirmed and guarded by ChatGPT foreground',
    () async {
      final actions = _RecordingActions();
      var foreground = false;
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _NoopDiscovery(),
        actions: actions,
        foregroundProbe: (app) async => app.id == 'chatgpt' && foreground,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      Future<void> press(String id) =>
          controller.executeRemote(RemoteActionRequest.button(id));

      for (final id in chatGptApprovalShortcutIds) {
        await expectLater(press(id), throwsStateError);
        await expectLater(
          press(confirmedChatGptApprovalShortcutId(id)),
          throwsStateError,
        );
      }
      expect(actions.executed, isEmpty);
      foreground = true;
      await expectLater(press('codex.approve'), throwsStateError);
      await expectLater(press('vibe.codex.decline'), throwsStateError);
      await expectLater(
        press('chatgpt.codex.send.confirmed'),
        throwsFormatException,
      );
      await expectLater(press(chatGptFastModeShortcutId), throwsStateError);
      await expectLater(press(chatGptBranchOffShortcutId), throwsStateError);
      await expectLater(
        press(chatGptLocalDictationShortcutId),
        throwsStateError,
      );
      expect(actions.executed, isEmpty);

      final fast = controller.manifest.buttonById(chatGptFastModeShortcutId)!;
      await controller.updateButton(
        'chatgpt',
        fast.copyWith(shortcut: const ['CTRL', 'SHIFT', 'F9'], enabled: true),
      );
      await press(chatGptFastModeShortcutId);
      await press(confirmedChatGptApprovalShortcutId(chatGptApproveShortcutId));
      await press(confirmedChatGptApprovalShortcutId(chatGptDeclineShortcutId));
      await press('codex.send');
      expect(actions.executed, [
        '$chatGptFastModeShortcutId:chatgpt',
        '$chatGptApproveShortcutId:chatgpt',
        '$chatGptDeclineShortcutId:chatgpt',
        'chatgpt.codex.send:chatgpt',
      ]);
    },
  );

  test(
    'a deliberate Windows Voice binding survives transfer and sends keys',
    () async {
      final actions = _RecordingActions();
      final store = MemoryDesktopConfigStore();
      final controller = DesktopController(
        store: store,
        discovery: _NoopDiscovery(),
        actions: actions,
        foregroundProbe: (app) async => app.id == 'chatgpt',
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      const id = chatGptNativeVoiceShortcutId;
      const keys = ['CTRL', 'SHIFT', 'V'];
      final unbound = controller.manifest.buttonById(id)!;
      expect(unbound.enabled, isFalse);
      await expectLater(
        controller.executeRemote(const RemoteActionRequest.button(id)),
        throwsStateError,
      );
      await controller.updateButton('chatgpt', unbound);
      expect(controller.manifest.buttonById(id)!.enabled, isFalse);

      await controller.updateButton(
        'chatgpt',
        unbound.copyWith(shortcut: keys, enabled: true),
      );
      const transfer = DesktopShortcutTransferService();
      final exported = transfer.encode(store.value!);
      await controller.importShortcutLayouts(transfer.decode(exported));
      final button = controller.manifest.buttonById(id)!;
      expect(button.targetType, RemoteTargetType.keyboardShortcut);
      expect(button.shortcut, keys);
      expect(button.enabled, isTrue);
      await controller.executeRemote(const RemoteActionRequest.button(id));
      expect(actions.executed, ['$id:chatgpt']);
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows Vibe injection checks approved foreground in the SendKeys process',
    () async {
      if (!Platform.isWindows) return;
      final runner = _ProcessRunner();
      final actions = DesktopActions(runner: runner, environment: const {});
      await actions.sendShortcut(const [
        'PRIMARY',
        'N',
      ], expectedAppId: 'cursor');
      final args = runner.calls.single.$2;
      final script = args[3];
      expect(script, contains('& {'));
      expect(script, contains('GetForegroundWindow'));
      expect(script, contains(r'SendWait($keyStroke)'));
      expect(script.endsWith('\n'), isFalse);
      expect(args[4], "'cursor'");
      expect(args[5], "'^n'");
    },
  );
}
