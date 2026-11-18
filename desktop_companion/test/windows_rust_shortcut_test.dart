import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/windows_shortcut_backend.dart';
import 'package:path/path.dart' as path;

class _RecordingLegacy implements DesktopProcessRunner {
  int calls = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls++;
    return ProcessResult(1, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) {
    throw StateError('Unexpected detached process');
  }
}

class _RecordingRust implements WindowsShortcutBackend {
  _RecordingRust({this.failure});

  final StateError? failure;
  final shortcuts = <WindowsShortcut>[];

  @override
  Future<void> send(WindowsShortcut shortcut) async {
    shortcuts.add(shortcut);
    if (failure case final failure?) throw failure;
  }
}

const _rustEnvironment = {windowsShortcutBackendEnvironment: 'rust'};

void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/windows_shortcuts.json').readAsStringSync(),
          )
          as Map<String, Object?>;

  for (final example
      in (fixture['accepted'] as List).cast<Map<String, Object?>>()) {
    test('Rust route accepts ${example['id']}', () async {
      final legacy = _RecordingLegacy();
      final rust = _RecordingRust();
      final actions = DesktopActions(
        platformOverride: TargetPlatform.windows,
        runner: legacy,
        environment: _rustEnvironment,
        loadWindowsShortcutBackend: () => rust,
      );
      await actions.sendShortcut(
        (example['keys'] as List).cast<String>(),
        expectedAppId: example['target'] as String?,
      );
      final request = rust.shortcuts.single;
      expect(request.key, example['key']);
      expect(
        request.modifiers.map(
          (modifier) => switch (modifier) {
            WindowsShortcutModifier.control => 'CTRL',
            WindowsShortcutModifier.alt => 'ALT',
            WindowsShortcutModifier.shift => 'SHIFT',
          },
        ),
        example['modifiers'],
      );
      expect(request.allowedProcesses, example['allowedProcesses'] ?? []);
      expect(legacy.calls, 0);
    });
  }

  for (final example
      in (fixture['rejected'] as List).cast<Map<String, Object?>>()) {
    test('Rust route rejects ${example['id']} before loading', () async {
      final legacy = _RecordingLegacy();
      final actions = DesktopActions(
        platformOverride: TargetPlatform.windows,
        runner: legacy,
        environment: _rustEnvironment,
        loadWindowsShortcutBackend: () => throw StateError('Unexpected load'),
      );
      await expectLater(
        actions.sendShortcut((example['keys'] as List).cast<String>()),
        throwsFormatException,
      );
      expect(legacy.calls, 0);
    });
  }

  test('Windows shortcut backend selection is fixed at construction', () async {
    final legacy = _RecordingLegacy();
    final environment = <String, String>{};
    final actions = DesktopActions(
      platformOverride: TargetPlatform.windows,
      runner: legacy,
      environment: environment,
      loadWindowsShortcutBackend: () => throw StateError('Unexpected load'),
    );
    environment.addAll(_rustEnvironment);
    await actions.sendShortcut(const ['CTRL', 'T']);
    expect(legacy.calls, 1);
  });

  test('explicit Rust opt-in does not affect Linux input', () async {
    final legacy = _RecordingLegacy();
    final actions = DesktopActions(
      platformOverride: TargetPlatform.linux,
      runner: legacy,
      environment: {..._rustEnvironment, 'DISPLAY': ':99'},
      loadWindowsShortcutBackend: () => throw StateError('Unexpected load'),
    );
    await actions.sendShortcut(const ['CTRL', 'T']);
    expect(legacy.calls, 1);
  });

  test('an unknown guarded Rust target is rejected before delivery', () async {
    final legacy = _RecordingLegacy();
    final actions = DesktopActions(
      platformOverride: TargetPlatform.windows,
      runner: legacy,
      environment: _rustEnvironment,
      loadWindowsShortcutBackend: () => throw StateError('Unexpected load'),
    );
    await expectLater(
      actions.sendShortcut(const ['CTRL', 'T'], expectedAppId: 'unknown'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Unsupported Windows shortcut target.',
        ),
      ),
    );
    expect(legacy.calls, 0);
  });

  test('Rust loads once, and partial failure causes no replay', () async {
    final legacy = _RecordingLegacy();
    final error = StateError('Windows accepted only part of the shortcut.');
    final rust = _RecordingRust(failure: error);
    var loadCalls = 0;
    final actions = DesktopActions(
      platformOverride: TargetPlatform.windows,
      runner: legacy,
      environment: _rustEnvironment,
      loadWindowsShortcutBackend: () {
        loadCalls++;
        return rust;
      },
    );
    await expectLater(
      actions.sendShortcut(const ['CTRL', 'T']),
      throwsA(same(error)),
    );
    expect(rust.shortcuts, hasLength(1));
    expect(legacy.calls, 0);
    await expectLater(
      actions.sendShortcut(const ['CTRL', 'N']),
      throwsA(same(error)),
    );
    expect(rust.shortcuts.map((shortcut) => shortcut.key), ['T', 'N']);
    expect(loadCalls, 1);
    expect(legacy.calls, 0);
  });

  test(
    'missing Rust library reports a stable failure without fallback',
    () async {
      final legacy = _RecordingLegacy();
      final sandbox = Directory.systemTemp.createTempSync(
        'lumiakeys-dll-test-',
      );
      addTearDown(() => sandbox.deleteSync());
      final actions = DesktopActions(
        platformOverride: TargetPlatform.windows,
        runner: legacy,
        environment: _rustEnvironment,
        loadWindowsShortcutBackend: () => RustWindowsShortcutBackend.fromPath(
          path.join(sandbox.path, windowsShortcutLibraryName),
        ),
      );
      await expectLater(
        actions.sendShortcut(const ['CTRL', 'T']),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The Rust shortcut backend could not be loaded.',
          ),
        ),
      );
      expect(legacy.calls, 0);
    },
  );

  final dll = Platform.environment['LUMIAKEY_TEST_WINDOWS_SHORTCUT_DLL'];
  test(
    'packaged Rust DLL exposes ABI v1 and rejects invalid keys',
    () async {
      final rust = RustWindowsShortcutBackend.fromPath(dll!);
      await expectLater(
        rust.send(
          const WindowsShortcut(
            key: 'F13',
            modifiers: [],
            allowedProcesses: [],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Invalid Windows shortcut request.',
          ),
        ),
      );
    },
    skip: Platform.isWindows && dll != null
        ? false
        : 'Requires the packaged Windows shortcut DLL',
  );
}
