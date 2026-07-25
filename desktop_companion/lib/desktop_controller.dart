import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_actions.dart';

abstract interface class DesktopConfigStore {
  Future<DesktopManifest?> load();
  Future<void> save(DesktopManifest manifest);
}

class SharedPreferencesDesktopConfigStore implements DesktopConfigStore {
  SharedPreferencesDesktopConfigStore({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();

  static const storageKey = 'lumiakeys.desktop.manifest.v1';
  final SharedPreferencesAsync preferences;

  @override
  Future<DesktopManifest?> load() async {
    final raw = await preferences.getString(storageKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid desktop config');
    return DesktopManifest.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<void> save(DesktopManifest manifest) =>
      preferences.setString(storageKey, jsonEncode(manifest.toJson()));
}

class MemoryDesktopConfigStore implements DesktopConfigStore {
  DesktopManifest? value;
  int saveCount = 0;

  @override
  Future<DesktopManifest?> load() async => value;

  @override
  Future<void> save(DesktopManifest manifest) async {
    value = manifest;
    saveCount++;
  }
}

abstract interface class ApplicationDiscovery {
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps);
}

class PlatformApplicationDiscovery implements ApplicationDiscovery {
  const PlatformApplicationDiscovery();

  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async {
    final installedMacApps = Platform.isMacOS
        ? await _macApplicationNames()
        : const <String>[];
    final installedWindowsApps = Platform.isWindows
        ? await _windowsApplicationNames()
        : const <String>[];
    final runningProcesses = await _runningProcessNames();
    final foregroundProcess = await _foregroundProcessName();
    return Future.wait(
      apps.map((app) async {
        final candidates = _candidateNames(app);
        final running = runningProcesses.any(
          (process) => candidates.any(process.contains),
        );
        final foreground =
            foregroundProcess != null &&
            running &&
            candidates.any(foregroundProcess.contains);
        if (Platform.isMacOS) {
          final chatGptDetected =
              app.id == 'codex' &&
              (installedMacApps.any(
                    (installed) => installed.contains('chatgpt'),
                  ) ||
                  runningProcesses.any(
                    (process) => process.contains('chatgpt'),
                  ));
          final detected = installedMacApps.any(
            (installed) => candidates.any(installed.contains),
          );
          return app.copyWith(
            detected: detected || running,
            running: running,
            foreground: foreground,
            executable: chatGptDetected ? 'ChatGPT' : app.executable,
          );
        }
        if (Platform.isWindows) {
          final executable = _windowsExecutable(app);
          final result = await Process.run('where.exe', [executable]);
          final resolved = result.exitCode == 0
              ? result.stdout.toString().split(RegExp(r'[\r\n]+')).first.trim()
              : executable;
          final detectedByName = installedWindowsApps.any(
            (installed) => candidates.any(installed.contains),
          );
          return app.copyWith(
            detected: result.exitCode == 0 || detectedByName || running,
            running: running,
            foreground: foreground,
            executable: result.exitCode == 0 ? resolved : app.executable,
          );
        }
        final result = await Process.run('which', [app.executable]);
        return app.copyWith(
          detected: result.exitCode == 0 || running,
          running: running,
          foreground: foreground,
        );
      }),
    );
  }

  static Future<List<String>> _macApplicationNames() async {
    final names = <String>[];
    for (final root in ['/Applications', '/System/Applications']) {
      final directory = Directory(root);
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory && entity.path.endsWith('.app')) {
          names.add(
            entity.uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .last
                .replaceAll('.app', '')
                .toLowerCase(),
          );
        }
      }
    }
    return names;
  }

  static List<String> _candidateNames(RemoteApplication app) {
    final name = app.name.toLowerCase();
    return [
      name,
      app.executable.toLowerCase(),
      if (app.id == 'vscode') 'visual studio code',
      if (app.id == 'premiere') 'premiere pro',
      if (app.id == 'vscode') 'code.exe',
      if (app.id == 'chrome') 'chrome.exe',
      if (app.id == 'photoshop') 'photoshop.exe',
      if (app.id == 'illustrator') 'illustrator.exe',
      if (app.id == 'premiere') 'adobe premiere pro.exe',
      if (app.id == 'codex') 'codex.exe',
      if (app.id == 'codex') 'chatgpt',
      if (app.id == 'codex') 'chatgpt.app',
    ];
  }

  static Future<List<String>> _windowsApplicationNames() async {
    final result = await Process.run('powershell.exe', const [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'$paths = @('
          r"'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',"
          r"'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',"
          r"'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'); "
          r'Get-ItemProperty $paths -ErrorAction SilentlyContinue | '
          r'Where-Object DisplayName | Select-Object -ExpandProperty DisplayName; '
          r'Get-StartApps | Select-Object -ExpandProperty Name',
    ]);
    if (result.exitCode != 0) return const [];
    return _normalizedLines(result.stdout);
  }

  static Future<List<String>> _runningProcessNames() async {
    ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('tasklist.exe', const ['/FO', 'CSV', '/NH']);
    } else {
      result = await Process.run('ps', const ['-axo', 'comm=']);
    }
    if (result.exitCode != 0) return const [];
    return _normalizedLines(result.stdout);
  }

  /// Obtains only the process name needed to map the OS foreground window to a
  /// Desktop-owned application record. The value is never sent as a command or
  /// executable path to the phone.
  static Future<String?> _foregroundProcessName() async {
    ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('/usr/bin/osascript', const [
        '-e',
        'tell application "System Events" to get name of first application process whose frontmost is true',
      ]);
    } else if (Platform.isWindows) {
      result = await Process.run('powershell.exe', const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Add-Type @"'
            r'using System; using System.Runtime.InteropServices; '
            r'public static class LK { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); '
            r'[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId); }'
            r'"@; $id = 0; [LK]::GetWindowThreadProcessId([LK]::GetForegroundWindow(), [ref]$id) | Out-Null; '
            r'if ($id -ne 0) { (Get-Process -Id $id).ProcessName }',
      ]);
    } else {
      final window = await Process.run('xdotool', const [
        'getactivewindow',
        'getwindowpid',
      ]);
      if (window.exitCode != 0) return null;
      final pid = int.tryParse(window.stdout.toString().trim());
      if (pid == null) return null;
      result = await Process.run('ps', ['-p', '$pid', '-o', 'comm=']);
    }
    if (result.exitCode != 0) return null;
    final name = result.stdout.toString().trim().toLowerCase();
    return name.isEmpty ? null : name;
  }

  static List<String> _normalizedLines(Object? value) => value
      .toString()
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.toLowerCase().replaceAll('"', '').trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  static String _windowsExecutable(RemoteApplication app) => switch (app.id) {
    'vscode' => 'Code.exe',
    'chrome' => 'chrome.exe',
    'photoshop' => 'Photoshop.exe',
    'illustrator' => 'Illustrator.exe',
    'premiere' => 'Adobe Premiere Pro.exe',
    'codex' => 'Codex.exe',
    _ => app.executable,
  };
}

class DesktopController extends ChangeNotifier {
  DesktopController({
    required this.store,
    DesktopActions? actions,
    ApplicationDiscovery? discovery,
  }) : actions = actions ?? DesktopActions(),
       discovery = discovery ?? const PlatformApplicationDiscovery();

  final DesktopConfigStore store;
  final DesktopActions actions;
  final ApplicationDiscovery discovery;

  DesktopManifest _manifest = DesktopManifest.starter();
  bool _loading = true;
  String? _error;
  String? _connectedPhone;
  int _selectedSection = 0;
  bool _initialized = false;
  bool _refreshingApplications = false;
  Timer? _applicationMonitor;

  DesktopManifest get manifest => _manifest;
  bool get loading => _loading;
  String? get error => _error;
  String? get connectedPhone => _connectedPhone;
  int get selectedSection => _selectedSection;
  RemoteApplication? get foregroundApplication =>
      _manifest.applications.cast<RemoteApplication?>().firstWhere(
        (application) => application?.foreground == true,
        orElse: () => null,
      );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final loaded = await store.load() ?? DesktopManifest.starter();
      _manifest = _upgradeManifest(loaded);
      final apps = await discovery.refresh(_manifest.applications);
      _manifest = _manifest.copyWith(applications: apps);
      if (jsonEncode(_manifest.toJson()) != jsonEncode(loaded.toJson())) {
        _manifest = _manifest.copyWith(revision: loaded.revision + 1);
      }
      await store.save(_manifest);
    } catch (error) {
      _error = '$error';
      _manifest = DesktopManifest.starter();
    } finally {
      _loading = false;
      notifyListeners();
      if (discovery is PlatformApplicationDiscovery) {
        _applicationMonitor = Timer.periodic(
          const Duration(seconds: 3),
          (_) => unawaited(_refreshRuntimeApplications()),
        );
      }
    }
  }

  void selectSection(int index) {
    if (_selectedSection == index) return;
    _selectedSection = index;
    notifyListeners();
  }

  void recordConnectedPhone(String address) {
    if (_connectedPhone == address) return;
    _connectedPhone = address;
    notifyListeners();
  }

  Future<void> updateSettings(RemoteSettings settings) =>
      _commit(_manifest.copyWith(settings: settings));

  Future<void> updateButton(
    String layoutId,
    RemoteShortcutButton updated,
  ) async {
    final layouts = _manifest.layouts
        .map((layout) {
          if (layout.id != layoutId) return layout;
          final buttons = layout.buttons
              .map((button) => button.id == updated.id ? updated : button)
              .toList(growable: false);
          return layout.copyWith(buttons: buttons);
        })
        .toList(growable: false);
    await _commit(_manifest.copyWith(layouts: layouts));
  }

  Future<void> updateApplication(RemoteApplication updated) async {
    final apps = _manifest.applications
        .map((app) => app.id == updated.id ? updated : app)
        .toList(growable: false);
    await _commit(_manifest.copyWith(applications: apps));
  }

  Future<void> refreshApplications() async {
    try {
      final apps = await discovery.refresh(_manifest.applications);
      await _commit(_manifest.copyWith(applications: apps));
      _error = null;
    } catch (error) {
      _error = 'App discovery failed: $error';
      notifyListeners();
    }
  }

  Future<void> _refreshRuntimeApplications() async {
    if (_refreshingApplications) return;
    _refreshingApplications = true;
    try {
      final apps = await discovery.refresh(_manifest.applications);
      if (!_sameApplications(apps, _manifest.applications)) {
        await _commit(_manifest.copyWith(applications: apps));
      }
    } catch (error) {
      _error = 'App monitor failed: $error';
      notifyListeners();
    } finally {
      _refreshingApplications = false;
    }
  }

  static bool _sameApplications(
    List<RemoteApplication> left,
    List<RemoteApplication> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.name != b.name ||
          a.icon != b.icon ||
          a.executable != b.executable ||
          a.layoutId != b.layoutId ||
          a.detected != b.detected ||
          a.running != b.running ||
          a.foreground != b.foreground) {
        return false;
      }
    }
    return true;
  }

  static DesktopManifest _upgradeManifest(DesktopManifest manifest) {
    final starter = DesktopManifest.starter();
    const legacyIds = {'windows', 'mac', 'photoshop', 'vscode', 'premiere'};
    final profiles = manifest.profiles
        .where((profile) => !legacyIds.contains(profile.id))
        .toList(growable: false);
    if (profiles.isEmpty) return starter;
    final starterCodex = starter.layoutById('codex')!;
    final starterChrome = starter.layoutById('app.chrome')!;
    final hasCurrentCodexActions =
        manifest.buttonById('codex.open') != null &&
        manifest.buttonById('codex.voice') != null &&
        manifest.buttonById('codex.newChat') != null &&
        manifest.buttonById('codex.searchChats') != null &&
        manifest.buttonById('codex.review') != null;
    final hasCurrentChromeActions =
        manifest.buttonById('chrome.bookmark') != null &&
        manifest.buttonById('chrome.nextTab') != null &&
        manifest.buttonById('chrome.passwordManager') != null &&
        manifest.buttonById('chrome.mute') != null;
    final layouts = manifest.layouts
        .map((layout) {
          if (layout.id == 'codex' && !hasCurrentCodexActions) {
            return starterCodex;
          }
          if (layout.id == 'app.chrome' && !hasCurrentChromeActions) {
            final existingById = {
              for (final button in layout.buttons) button.id: button,
            };
            return starterChrome.copyWith(
              name: layout.name,
              buttons: starterChrome.buttons
                  .map((button) => existingById[button.id] ?? button)
                  .toList(growable: false),
            );
          }
          return layout;
        })
        .toList(growable: true);
    if (!layouts.any((layout) => layout.id == 'codex')) {
      layouts.add(starterCodex);
    }
    final starterCodexApp = starter.applicationById('codex')!;
    final applications = manifest.applications
        .map(
          (application) => application.id == 'codex'
              ? application.copyWith(name: starterCodexApp.name)
              : application,
        )
        .toList(growable: true);
    for (final starterApp in starter.applications) {
      if (!applications.any((application) => application.id == starterApp.id)) {
        applications.add(starterApp);
      }
    }
    final currentProfileId =
        profiles.any((profile) => profile.id == manifest.currentProfileId)
        ? manifest.currentProfileId
        : profiles.first.id;
    return manifest.copyWith(
      layouts: layouts,
      applications: applications,
      profiles: profiles,
      currentProfileId: currentProfileId,
    );
  }

  Future<void> switchProfile(String profileId) async {
    if (!_manifest.profiles.any((profile) => profile.id == profileId)) {
      throw const FormatException('Unknown shortcut profile');
    }
    await _commit(_manifest.copyWith(currentProfileId: profileId));
  }

  Future<void> executeRemote(RemoteActionRequest request) async {
    switch (request.kind) {
      case RemoteActionKind.button:
        final button = _manifest.buttonById(request.buttonId ?? '');
        if (button == null) throw const FormatException('Unknown button');
        await actions.executeButton(button, _manifest);
      case RemoteActionKind.launchApplication:
        if (!_manifest.settings.autoLaunchApps) {
          throw StateError('Automatic app launching is disabled');
        }
        final app = _manifest.applicationById(request.applicationId ?? '');
        if (app == null) throw const FormatException('Unknown application');
        await actions.launchApplication(app.executable);
      case RemoteActionKind.switchProfile:
        await switchProfile(request.profileId ?? '');
    }
  }

  Future<void> executeLegacy(Map<String, Object?> request) =>
      actions.executeLegacy(request);

  Future<void> _commit(DesktopManifest next) async {
    final revised = next.copyWith(revision: _manifest.revision + 1);
    revised.validate();
    await store.save(revised);
    _manifest = revised;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _applicationMonitor?.cancel();
    super.dispose();
  }
}
