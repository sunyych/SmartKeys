import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';

class _Runner implements DesktopProcessRunner {
  final calls = <({String exe, List<String> args})>[];
  bool available = true;
  String foreground = 'cursor';
  @override
  Future<ProcessResult> run(String exe, List<String> args) async {
    calls.add((exe: exe, args: args));
    if (exe == 'xdotool' && args.first == 'getmouselocation') {
      return ProcessResult(
        1,
        available ? 0 : 1,
        'X=10\nY=20\nSCREEN=0\nWINDOW=0\n',
        '',
      );
    }
    if (exe == 'xdotool' && args.first == 'getactivewindow') {
      return ProcessResult(1, 0, '123', '');
    }
    if (exe == 'ps') return ProcessResult(1, 0, foreground, '');
    if (exe == 'pactl' && args.first == 'get-sink-mute') {
      return ProcessResult(1, 0, 'Mute: no', '');
    }
    return ProcessResult(1, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> args) =>
      throw UnimplementedError();
}

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

void main() {
  test(
    'X11 readiness requires a working xdotool; Wayland never advertises pointer',
    () async {
      final runner = _Runner();
      final x11 = DesktopActions(
        runner: runner,
        platformOverride: TargetPlatform.linux,
        environment: const {'DISPLAY': ':99'},
      );
      expect(await x11.probePointerSupport(), isTrue);
      runner.available = false;
      expect(await x11.probePointerSupport(), isFalse);
      final wayland = DesktopActions(
        runner: runner,
        platformOverride: TargetPlatform.linux,
        environment: const {'DISPLAY': ':99', 'WAYLAND_DISPLAY': 'wayland-0'},
      );
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        actions: wayland,
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      final server = CompanionServer(
        controller: controller,
        discoveryPort: 45848,
      );
      await server.start();
      addTearDown(server.dispose);
      expect(server.capabilities, isNot(contains('mouse-control-v1')));
      expect(server.capabilities, isNot(contains('local-dictation-v1')));
      await expectLater(
        wayland.applyPointerInputs(const [PointerInput.move(1, 2)]),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'Linux clipboard, bounded pointer batches and media use supported tools',
    () async {
      final runner = _Runner();
      final actions = DesktopActions(
        runner: runner,
        platformOverride: TargetPlatform.linux,
        environment: const {'DISPLAY': ':99'},
      );
      await actions.sendShortcut(const ['PRIMARY', 'C']);
      expect(runner.calls.last.args, ['key', '--clearmodifiers', 'ctrl+c']);
      await actions.applyPointerInputs(const [
        PointerInput.move(2, -3),
        PointerInput.scroll(3),
        PointerInput.button(secondary: true),
      ]);
      expect(
        runner.calls.any(
          (call) => listEquals(call.args, [
            'click',
            '--repeat',
            '3',
            '--delay',
            '0',
            '4',
          ]),
        ),
        isTrue,
      );
      final manifest = DesktopManifest.regularStarter();
      for (final id in ['volumeUp', 'volumeDown', 'mute', 'playPause']) {
        await actions.executeButton(
          manifest.buttonById('keyboard.$id')!,
          manifest,
        );
      }
      expect(
        runner.calls.any(
          (call) => call.exe == 'playerctl' && call.args.single == 'play-pause',
        ),
        isTrue,
      );
      expect(
        runner.calls.any(
          (call) => call.exe == 'pactl' && call.args.contains('+5%'),
        ),
        isTrue,
      );
      expect(
        runner.calls.any(
          (call) => call.exe == 'pactl' && call.args.contains('-5%'),
        ),
        isTrue,
      );
      await expectLater(
        actions.applyPointerInputs(const [PointerInput.move(128, 0)]),
        throwsFormatException,
      );
    },
  );
  test(
    'Linux fixed Vibe actions check foreground and never use an absent native channel',
    () async {
      final runner = _Runner();
      final actions = DesktopActions(
        runner: runner,
        platformOverride: TargetPlatform.linux,
        environment: const {'DISPLAY': ':99'},
      );
      final manifest = DesktopManifest.starter();
      await actions.executeButton(
        manifest.buttonById('vibe.cursor.quote')!,
        manifest,
        expectedAppId: 'cursor',
      );
      expect(
        runner.calls.any(
          (call) =>
              call.exe == 'xdotool' &&
              call.args.first == 'type' &&
              call.args.last == '""',
        ),
        isTrue,
      );
      await expectLater(
        actions.executeButton(
          manifest.buttonById('vibe.cursor.screenshot')!,
          manifest,
          expectedAppId: 'cursor',
        ),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'Linux Edge and browser navigation use X11 key symbols after foreground validation',
    () async {
      final runner = _Runner()..foreground = 'microsoft-edge-stable';
      final actions = DesktopActions(
        runner: runner,
        platformOverride: TargetPlatform.linux,
        environment: const {'DISPLAY': ':99'},
      );
      await actions.sendShortcut(const ['CTRL', 'R'], expectedAppId: 'edge');
      expect(runner.calls.first.args, ['getactivewindow', 'getwindowpid']);
      expect(runner.calls[1].exe, 'ps');
      expect(runner.calls.last.args, ['key', '--clearmodifiers', 'ctrl+r']);
      await actions.sendShortcut(const ['BROWSER_BACK']);
      expect(runner.calls.last.args, ['key', '--clearmodifiers', 'alt+Left']);
    },
  );
  test(
    'Linux command runner fixes the parsing locale',
    () async {
      final result = await const SystemDesktopProcessRunner().run(
        'pactl',
        const ['get-sink-mute', '@DEFAULT_SINK@'],
      );
      expect(result.stdout.toString(), matches(RegExp(r'^Mute: (yes|no)\s*$')));
    },
    skip:
        !Platform.isLinux ||
        Platform.environment['SMARTKEYS_LINUX_AUDIO_TEST'] != '1',
  );
}
