import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_native_backend.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

const _x11 = {'DISPLAY': ':99'};
const _firefox = RemoteApplication(
  id: 'firefox',
  name: 'Firefox',
  executable: 'Firefox',
  icon: 'firefox',
  layoutId: 'app.firefox',
);

class _NativeProcesses extends Fake implements NativeDesktopBackend {
  _NativeProcesses({this.foreground, this.failReads = false});

  final String? foreground;
  final bool failReads;
  int snapshots = 0;
  int foregroundReads = 0;

  @override
  Future<DesktopProcessSnapshot> readProcesses() async {
    snapshots++;
    if (failReads) throw StateError('Synthetic Linux snapshot failure');
    return DesktopProcessSnapshot(
      runningProcesses: const ['firefox'],
      foregroundProcess: foreground,
    );
  }

  @override
  Future<String?> readForegroundProcess() async {
    foregroundReads++;
    if (failReads) throw StateError('Synthetic Linux foreground read failure');
    return foreground;
  }
}

enum _Probe { executable, running, activePid, foreground }

class _ReadOnlyRunner {
  final probes = <_Probe>[];

  Future<ProcessResult> call(String command, List<String> arguments) async {
    switch (command) {
      case 'which':
        probes.add(_Probe.executable);
        return ProcessResult(1, 0, '/fixture/bin/firefox\n', '');
      case 'ps' when arguments.first == '-axo':
        probes.add(_Probe.running);
        expect(arguments, ['-axo', 'comm=']);
        return ProcessResult(1, 0, 'firefox\n', '');
      case 'xdotool':
        probes.add(_Probe.activePid);
        expect(arguments, ['getactivewindow', 'getwindowpid']);
        return ProcessResult(1, 0, '1234\n', '');
      case 'ps' when arguments.first == '-p':
        probes.add(_Probe.foreground);
        expect(arguments, ['-p', '1234', '-o', 'comm=']);
        return ProcessResult(1, 0, 'firefox\n', '');
      default:
        throw StateError('Unexpected process probe $command');
    }
  }
}

void main() {
  group('Linux Rust process discovery', () {
    test(
      'one Rust snapshot supplies both running and foreground flags',
      () async {
        final native = _NativeProcesses(foreground: 'firefox');
        final runner = _ReadOnlyRunner();
        final discovery = PlatformApplicationDiscovery(
          desktopBackend: native,
          runProcess: runner.call,
          environment: _x11,
        );

        final app = (await discovery.refresh([_firefox])).single;
        expect(app.running, isTrue);
        expect(app.foreground, isTrue);
        expect(native.snapshots, 1);
        expect(native.foregroundReads, 0);
        expect(runner.probes, [_Probe.executable]);
      },
    );

    test(
      'native null foreground does not trigger an X11 shell probe',
      () async {
        final native = _NativeProcesses();
        final runner = _ReadOnlyRunner();
        final discovery = PlatformApplicationDiscovery(
          desktopBackend: native,
          runProcess: runner.call,
          environment: _x11,
        );

        final app = (await discovery.refresh([_firefox])).single;
        expect(app.running, isTrue);
        expect(app.foreground, isFalse);
        expect(await discovery.isForeground(_firefox), isFalse);
        expect(native.snapshots, 1);
        expect(native.foregroundReads, 1);
        expect(runner.probes, [_Probe.executable]);
      },
    );

    test(
      'read failures keep the existing read-only compatibility probes',
      () async {
        final native = _NativeProcesses(failReads: true);
        final runner = _ReadOnlyRunner();
        final discovery = PlatformApplicationDiscovery(
          desktopBackend: native,
          runProcess: runner.call,
          environment: _x11,
        );

        final app = (await discovery.refresh([_firefox])).single;
        expect(app.running, isTrue);
        expect(app.foreground, isTrue);
        expect(await discovery.isForeground(_firefox), isTrue);
        expect(native.snapshots, 1);
        expect(native.foregroundReads, 1);
        expect(runner.probes, [
          _Probe.running,
          _Probe.activePid,
          _Probe.foreground,
          _Probe.executable,
          _Probe.activePid,
          _Probe.foreground,
        ]);
      },
    );
    test(
      'Wayland permits process snapshots and skips standalone foreground probes',
      () async {
        final native = _NativeProcesses(failReads: true);
        final runner = _ReadOnlyRunner();
        final discovery = PlatformApplicationDiscovery(
          desktopBackend: native,
          runProcess: runner.call,
          environment: const {..._x11, 'XDG_SESSION_TYPE': 'wayland'},
        );

        final app = (await discovery.refresh([_firefox])).single;
        expect(app.running, isTrue);
        expect(app.foreground, isFalse);
        expect(await discovery.isForeground(_firefox), isFalse);
        expect(native.snapshots, 1);
        expect(native.foregroundReads, 0);
        expect(runner.probes, [_Probe.running, _Probe.executable]);
      },
    );
  }, skip: !Platform.isLinux);
}
