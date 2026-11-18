import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/windows_desktop_backend.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

const _chatGpt = RemoteApplication(
  id: 'chatgpt',
  name: 'ChatGPT',
  executable: 'ChatGPT.exe',
  icon: 'chatgpt',
  layoutId: 'app.chatgpt',
);

class _ProcessBackend extends Fake implements WindowsDesktopBackend {
  _ProcessBackend({this.foreground, this.failReads = false});

  final String? foreground;
  final bool failReads;
  int registryReads = 0;
  int snapshotReads = 0;
  int foregroundReads = 0;

  @override
  Future<WindowsRegistryInventory> readRegistry() async {
    registryReads++;
    return const WindowsRegistryInventory(installedNames: [], appPaths: []);
  }

  @override
  Future<WindowsProcessSnapshot> readProcesses() async {
    snapshotReads++;
    if (failReads) throw StateError('Synthetic snapshot read failure');
    return WindowsProcessSnapshot(
      runningProcesses: const ['chatgpt.exe'],
      foregroundProcess: foreground,
    );
  }

  @override
  Future<String?> readForegroundProcess() async {
    foregroundReads++;
    if (failReads) throw StateError('Synthetic foreground read failure');
    return foreground;
  }
}

enum _Probe { startApps, executable, tasklist, foreground }

class _ProcessRunner {
  final probes = <_Probe>[];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    switch (executable) {
      case 'where.exe':
        probes.add(_Probe.executable);
        expect(arguments, ['ChatGPT.exe']);
        return ProcessResult(1, 1, '', '');
      case 'tasklist.exe':
        probes.add(_Probe.tasklist);
        expect(arguments, ['/FO', 'CSV', '/NH']);
        return ProcessResult(1, 0, '"ChatGPT.exe","1234","Console"\n', '');
      case 'powershell.exe' when arguments.last.contains('Get-StartApps'):
        probes.add(_Probe.startApps);
        expect(arguments.last, isNot(contains('Uninstall')));
        return ProcessResult(1, 0, '', '');
      case 'powershell.exe' when arguments.last.contains('GetForegroundWindow'):
        probes.add(_Probe.foreground);
        return ProcessResult(1, 0, 'ChatGPT\n', '');
      default:
        throw StateError('Unexpected process probe $executable');
    }
  }
}

void main() {
  group('Rust Windows process discovery', () {
    test('one native snapshot drives running and foreground state', () async {
      final backend = _ProcessBackend(foreground: 'chatgpt');
      final runner = _ProcessRunner();
      final discovery = PlatformApplicationDiscovery(
        windowsDesktopBackend: backend,
        runProcess: runner.call,
      );

      final app = (await discovery.refresh([_chatGpt])).single;

      expect(app.detected, isTrue);
      expect(app.running, isTrue);
      expect(app.foreground, isTrue);
      expect(backend.registryReads, 1);
      expect(backend.snapshotReads, 1);
      expect(backend.foregroundReads, 0);
      expect(runner.probes, [_Probe.startApps, _Probe.executable]);
    });

    test('native null foreground stays authoritative for ChatGPT', () async {
      final backend = _ProcessBackend();
      final runner = _ProcessRunner();
      final discovery = PlatformApplicationDiscovery(
        windowsDesktopBackend: backend,
        runProcess: runner.call,
      );

      final app = (await discovery.refresh([_chatGpt])).single;
      expect(app.running, isTrue);
      expect(app.foreground, isFalse);
      expect(await discovery.isForeground(_chatGpt), isFalse);
      expect(backend.snapshotReads, 1);
      expect(backend.foregroundReads, 1);
      expect(runner.probes, [_Probe.startApps, _Probe.executable]);
    });

    test(
      'native read exceptions use the corresponding legacy probes',
      () async {
        final backend = _ProcessBackend(failReads: true);
        final runner = _ProcessRunner();
        final discovery = PlatformApplicationDiscovery(
          windowsDesktopBackend: backend,
          runProcess: runner.call,
        );

        final app = (await discovery.refresh([_chatGpt])).single;
        expect(app.running, isTrue);
        expect(app.foreground, isTrue);
        expect(await discovery.isForeground(_chatGpt), isTrue);
        expect(backend.snapshotReads, 1);
        expect(backend.foregroundReads, 1);
        expect(runner.probes, [
          _Probe.startApps,
          _Probe.tasklist,
          _Probe.foreground,
          _Probe.executable,
          _Probe.foreground,
        ]);
      },
    );
  }, skip: !Platform.isWindows);
}
