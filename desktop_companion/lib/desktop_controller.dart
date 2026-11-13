import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  PlatformApplicationDiscovery();

  // ChatGPT and Codex can share one desktop process. The controller updates
  // this after an explicit phone activation so subsequent probes retain the
  // panel the user asked to open.
  String? preferredForegroundAppId;

  static const _macOnlyApplicationIds = {'appleMusic', 'finder', 'safari'};
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
    final foregroundAppId = resolveForegroundApplicationId(
      apps,
      foregroundProcess,
      preferredAppId: preferredForegroundAppId,
    );
    return Future.wait(
      apps.map((app) async {
        if (!Platform.isMacOS && _macOnlyApplicationIds.contains(app.id)) {
          return app.copyWith(
            detected: false,
            running: false,
            foreground: false,
          );
        }
        final candidates = _candidateNames(app);
        final running = runningProcesses.any(
          (process) => candidates.any(process.contains),
        );
        final foreground = running && foregroundAppId == app.id;
        if (Platform.isMacOS) {
          final chatGptDetected =
              (app.id == 'codex' || app.id == 'chatgpt') &&
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
          final chatGptDetected =
              (app.id == 'codex' || app.id == 'chatgpt') &&
              (installedWindowsApps.any(
                    (installed) => installed.contains('chatgpt'),
                  ) ||
                  runningProcesses.any(
                    (process) => process.contains('chatgpt'),
                  ));
          return app.copyWith(
            detected: result.exitCode == 0 || detectedByName || running,
            running: running,
            foreground: foreground,
            executable: chatGptDetected
                ? 'ChatGPT.exe'
                : result.exitCode == 0
                ? resolved
                : app.executable,
          );
        }
        if (app.id == 'safari') {
          return app.copyWith(
            detected: false,
            running: false,
            foreground: false,
          );
        }
        var linuxExecutableFound = false;
        for (final executable in _linuxExecutables(app)) {
          final result = await Process.run('which', [executable]);
          if (result.exitCode == 0) {
            linuxExecutableFound = true;
            break;
          }
        }
        return app.copyWith(
          detected: linuxExecutableFound || running,
          running: running,
          foreground: foreground,
        );
      }),
    );
  }

  static String? resolveForegroundApplicationId(
    List<RemoteApplication> apps,
    String? foregroundProcess, {
    String? preferredAppId,
  }) {
    if (foregroundProcess == null) return null;
    final process = _basename(foregroundProcess);
    final eligible = apps.where(
      (app) => !_macOnlyApplicationIds.contains(app.id) || Platform.isMacOS,
    );
    final exact = <RemoteApplication>[];
    final fallback = <RemoteApplication>[];
    for (final app in eligible) {
      final names = _candidateNames(app).map(_basename).toSet();
      if (names.contains(process)) {
        exact.add(app);
      } else if (names.any(
        (name) => name.length >= 5 && process.contains(name),
      )) {
        fallback.add(app);
      }
    }
    final matches = exact.isNotEmpty ? exact : fallback;
    if (matches.isEmpty) return null;
    // ChatGPT is the safe default for a shared ChatGPT process. Keep the last
    // explicitly selected panel when both IDs match that same process.
    if (preferredAppId != null &&
        matches.any((app) => app.id == preferredAppId)) {
      return preferredAppId;
    }
    if (process == 'chatgpt' && matches.any((app) => app.id == 'chatgpt')) {
      return 'chatgpt';
    }
    return matches.first.id;
  }

  static String _basename(String value) => value
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'\.exe$', caseSensitive: false), '')
      .toLowerCase();

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
      if (app.id == 'edge') 'msedge.exe',
      if (app.id == 'edge') 'msedge',
      if (app.id == 'edge') 'microsoft-edge-stable',
      if (app.id == 'firefox') 'firefox.exe',
      if (app.id == 'teams') 'ms-teams.exe',
      if (app.id == 'teams') 'teams.exe',
      if (app.id == 'zoom') 'zoom.exe',
      if (app.id == 'zoom') 'cpt-host.exe',
      if (app.id == 'safari') 'safari.app',
      if (app.id == 'photoshop') 'photoshop.exe',
      if (app.id == 'illustrator') 'illustrator.exe',
      if (app.id == 'premiere') 'adobe premiere pro.exe',
      if (app.id == 'codex') 'codex.exe',
      if (app.id == 'codex') 'chatgpt',
      if (app.id == 'codex') 'chatgpt.app',
      if (app.id == 'chatgpt') 'chatgpt.exe',
      if (app.id == 'chatgpt') 'chatgpt.app',
      if (app.id == 'claude') 'claude.exe',
      if (app.id == 'cursor') 'cursor.exe',
    ];
  }

  /// A fresh foreground probe used immediately before Vibe shortcut injection.
  Future<bool> isForeground(
    RemoteApplication app, {
    List<RemoteApplication>? applications,
  }) async {
    final foreground = await _foregroundProcessName();
    if (foreground == null) return false;
    final resolved = resolveForegroundApplicationId(
      applications ?? [app],
      foreground,
      preferredAppId: preferredForegroundAppId,
    );
    if (resolved == app.id) return true;
    // ChatGPT exposes both Chat and Codex modes from the same native window.
    // The process probe may retain either legacy app identity as the preferred
    // panel, but both IDs describe the same focused executable.
    return (resolved == 'chatgpt' || resolved == 'codex') &&
        (app.id == 'chatgpt' || app.id == 'codex') &&
        app.executable.toLowerCase().contains('chatgpt');
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
        r'Add-Type -TypeDefinition @"'
            '\n'
            r'using System; using System.Runtime.InteropServices; '
            r'public static class LK { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); '
            r'[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId); '
            r'[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint command); '
            r'[DllImport("user32.dll", EntryPoint="GetWindowLongW")] public static extern int GetWindowLong(IntPtr hWnd, int index); '
            r'[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd); }'
            '\n'
            r'"@; $windowPid = 0; $hwnd = [LK]::GetForegroundWindow(); [LK]::GetWindowThreadProcessId($hwnd, [ref]$windowPid) | Out-Null; '
            r'if ($windowPid -ne 0) { $name = (Get-Process -Id $windowPid).ProcessName; $style = [uint32][LK]::GetWindowLong($hwnd, -20); $owner = [LK]::GetWindow($hwnd, 4); '
            r'if ($name -ne "ChatGPT" -or ([LK]::IsWindowVisible($hwnd) -and ($style -band 0x80) -eq 0 -and ($style -band 0x08000000) -eq 0 -and $owner -eq [IntPtr]::Zero)) { $name } }',
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
    'chatgpt' => 'ChatGPT.exe',
    'codex' =>
      app.executable.toLowerCase().contains('chatgpt')
          ? 'ChatGPT.exe'
          : 'Codex.exe',
    'claude' => 'Claude.exe',
    'cursor' => 'Cursor.exe',
    'edge' => 'msedge.exe',
    'firefox' => 'firefox.exe',
    'teams' => 'ms-teams.exe',
    'zoom' => 'Zoom.exe',
    _ => app.executable,
  };

  static List<String> _linuxExecutables(RemoteApplication app) =>
      switch (app.id) {
        'edge' => const ['microsoft-edge', 'microsoft-edge-stable'],
        _ => [_linuxExecutable(app)],
      };

  static String _linuxExecutable(RemoteApplication app) => switch (app.id) {
    'chatgpt' => 'chatgpt',
    'edge' => 'microsoft-edge',
    'firefox' => 'firefox',
    'teams' => 'teams-for-linux',
    'zoom' => 'zoom',
    _ => app.executable,
  };
}

class DesktopController extends ChangeNotifier {
  DesktopController({
    required this.store,
    DesktopActions? actions,
    ApplicationDiscovery? discovery,
    this.foregroundProbe,
  }) : actions = actions ?? DesktopActions(),
       discovery = discovery ?? PlatformApplicationDiscovery();

  final DesktopConfigStore store;
  final DesktopActions actions;
  final ApplicationDiscovery discovery;
  final Future<bool> Function(RemoteApplication)? foregroundProbe;
  bool _managedActionRunning = false;
  int _applicationRefreshGeneration = 0;

  DesktopManifest _manifest = DesktopManifest.starter();
  bool _loading = true;
  String? _error;
  String? _connectedPhone;
  int _selectedSection = 0;
  bool _initialized = false;
  bool _refreshingApplications = false;
  Timer? _applicationMonitor;

  RemoteShortcutPlatform get _shortcutPlatform => Platform.isMacOS
      ? RemoteShortcutPlatform.apple
      : Platform.isWindows
      ? RemoteShortcutPlatform.windows
      : RemoteShortcutPlatform.other;

  DesktopManifest get manifest {
    final layouts = _manifest.layouts
        .map((layout) => projectChatGptLayout(layout, _shortcutPlatform))
        .toList(growable: false);
    return _manifest.copyWith(layouts: layouts);
  }

  /// Unprojected settings used by portable shortcut export.
  DesktopManifest get manifestForExport => _manifest;
  List<RemoteApplication> get applicationsForCurrentPlatform => _manifest
      .applications
      .where((app) => Platform.isMacOS || app.id != 'safari')
      .toList(growable: false);
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
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(_manifest.computerId ?? '')) {
        _manifest = _manifest.copyWith(computerId: _newComputerId());
      }
      _manifest = _applyPlatformDefaults(_manifest, loaded);
      final apps = await discovery.refresh(_manifest.applications);
      _manifest = _withApplications(apps);
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
              .map((button) {
                if (button.id != updated.id) return button;
                final projected =
                    projectChatGptLayout(
                      layout,
                      _shortcutPlatform,
                    ).buttons.firstWhere(
                      (candidate) => candidate.id == button.id,
                      orElse: () => button,
                    );
                final preservesPortableBinding =
                    layoutId == 'chatgpt' &&
                    _sameKeys(projected.shortcut, updated.shortcut);
                return preservesPortableBinding
                    ? updated.copyWith(shortcut: button.shortcut)
                    : updated;
              })
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

  Future<void> importShortcutLayouts(
    List<RemoteShortcutLayout> imported,
  ) async {
    if (imported.isEmpty) {
      throw const FormatException('No shortcut layouts to import');
    }
    final existingById = {
      for (final layout in _manifest.layouts) layout.id: layout,
    };
    for (final layout in imported) {
      final existing = existingById[layout.id];
      if (existing == null || existing.kind != layout.kind) {
        throw const FormatException(
          'Imported JSON contains an unknown shortcut layout',
        );
      }
      for (final button in layout.buttons) {
        if (button.targetType == RemoteTargetType.launchApplication &&
            _manifest.applicationById(button.target ?? '') == null) {
          throw const FormatException(
            'Imported shortcut references an unknown application',
          );
        }
      }
    }
    final importedById = {for (final layout in imported) layout.id: layout};
    final importedChatGpt = importedById['chatgpt'];
    if (importedChatGpt != null) {
      final currentChatGpt = _manifest.layoutById('chatgpt');
      if (currentChatGpt != null) {
        final projectedIds = projectChatGptLayout(
          currentChatGpt,
          _shortcutPlatform,
        ).buttons.map((button) => button.id).toSet();
        final importedIds = importedChatGpt.buttons
            .map((button) => button.id)
            .toSet();
        importedById['chatgpt'] = importedChatGpt.copyWith(
          buttons: [
            ...importedChatGpt.buttons,
            for (final button in currentChatGpt.buttons)
              if (!projectedIds.contains(button.id) &&
                  !importedIds.contains(button.id))
                button,
          ],
        );
      }
    }
    final candidate = _manifest.copyWith(
      layouts: _manifest.layouts
          .map((layout) => importedById[layout.id] ?? layout)
          .toList(growable: false),
    );
    candidate.validate();
    await _commit(candidate);
  }

  Future<void> refreshApplications() async {
    try {
      final apps = await discovery.refresh(_manifest.applications);
      await _commit(_withApplications(apps));
      _error = null;
    } catch (error) {
      _error = 'App discovery failed: $error';
      notifyListeners();
    }
  }

  Future<void> _refreshRuntimeApplications() async {
    if (_refreshingApplications || _managedActionRunning) return;
    _refreshingApplications = true;
    final generation = _applicationRefreshGeneration;
    try {
      final apps = await discovery.refresh(_manifest.applications);
      if (generation == _applicationRefreshGeneration &&
          !_managedActionRunning &&
          !_sameApplications(apps, _manifest.applications)) {
        await _commit(_withApplications(apps));
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

  DesktopManifest _withApplications(List<RemoteApplication> apps) {
    final previousForeground = foregroundApplication?.id;
    final nextForeground = apps.cast<RemoteApplication?>().firstWhere(
      (application) => application?.foreground == true,
      orElse: () => null,
    );
    final activationChanged =
        nextForeground != null && nextForeground.id != previousForeground;
    return _manifest.copyWith(
      applications: apps,
      applicationActivationSequence: activationChanged
          ? _manifest.applicationActivationSequence + 1
          : _manifest.applicationActivationSequence,
      activatedApplicationId: activationChanged
          ? nextForeground.id
          : _manifest.activatedApplicationId,
    );
  }

  static DesktopManifest _upgradeManifest(DesktopManifest manifest) {
    final starter = DesktopManifest.starter();
    const legacyIds = {'windows', 'mac', 'photoshop', 'vscode', 'premiere'};
    final profiles = manifest.profiles
        .where((profile) => !legacyIds.contains(profile.id))
        .toList(growable: false);
    if (profiles.isEmpty) return starter;
    final starterCodex = starter.layoutById('codex')!;
    final starterChatGpt = starter.layoutById('chatgpt')!;
    final starterChrome = starter.layoutById('app.chrome')!;
    final hasCurrentCodexActions =
        manifest.buttonById('codex.focusInput') != null &&
        manifest.buttonById('codex.voice') != null &&
        manifest.buttonById('codex.newChat') != null &&
        manifest.buttonById('codex.searchChats') != null &&
        manifest.buttonById('codex.review') != null;
    final hasCurrentChromeActions =
        manifest.buttonById('chrome.bookmark') != null &&
        manifest.buttonById('chrome.nextTab') != null &&
        manifest.buttonById('chrome.passwordManager') != null &&
        manifest.buttonById('chrome.mute') != null;
    final legacyCodexButtons = hasCurrentCodexActions
        ? manifest.layoutById('codex')!.buttons
        : starterCodex.buttons;
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
          if (layout.id == 'chatgpt') {
            final existingById = {
              for (final button in layout.buttons)
                if (button.id != 'chatgpt.codex.sidebar') button.id: button,
            };
            final intermediateCodexSidebar = layout.buttons
                .where((button) => button.id == 'chatgpt.codex.sidebar')
                .firstOrNull;
            final migratedCodexById = {
              for (final button in legacyCodexButtons)
                _canonicalLegacyCodexButtonId(button.id): _copyButtonWithId(
                  button,
                  _canonicalLegacyCodexButtonId(button.id),
                ),
            };
            final migratedVibeCodexById = {
              for (final button
                  in manifest.layoutById('vibe.codex')?.buttons ??
                      const <RemoteShortcutButton>[])
                _canonicalLegacyVibeCodexButtonId(button.id): _copyButtonWithId(
                  button,
                  _canonicalLegacyVibeCodexButtonId(button.id),
                ),
            };
            final starterIds = starterChatGpt.buttons
                .map((button) => button.id)
                .toSet();
            final defaultChatGptSidebar = starterChatGpt.buttons
                .where((button) => button.id == 'chatgpt.sidebar')
                .firstOrNull;
            final currentChatGptSidebar = existingById['chatgpt.sidebar'];
            final migratedCodexSidebar = migratedCodexById['chatgpt.sidebar'];
            bool isCustomSidebar(RemoteShortcutButton? button) =>
                button != null &&
                defaultChatGptSidebar != null &&
                !_sameKeys(button.shortcut, defaultChatGptSidebar.shortcut);
            final customLegacySidebar = [
              intermediateCodexSidebar,
              migratedCodexSidebar,
            ].where(isCustomSidebar).firstOrNull;
            final canonicalSidebar =
                !isCustomSidebar(currentChatGptSidebar) &&
                    customLegacySidebar != null
                ? customLegacySidebar
                : currentChatGptSidebar ??
                      intermediateCodexSidebar ??
                      migratedCodexSidebar;
            final extrasById = <String, RemoteShortcutButton>{};
            for (final entry in migratedCodexById.entries) {
              if (!starterIds.contains(entry.key)) {
                extrasById[entry.key] = entry.value;
              }
            }
            for (final entry in migratedVibeCodexById.entries) {
              if (!starterIds.contains(entry.key)) {
                extrasById[entry.key] = entry.value;
              }
            }
            for (final button in layout.buttons) {
              if (!starterIds.contains(button.id) &&
                  button.id != 'chatgpt.codex.sidebar') {
                extrasById[button.id] = button;
              }
            }
            final buttons = [
              for (final button in starterChatGpt.buttons)
                (button.id == 'chatgpt.sidebar' ? canonicalSidebar : null) ??
                    existingById[button.id] ??
                    migratedVibeCodexById[button.id] ??
                    migratedCodexById[button.id] ??
                    button,
              ...extrasById.values,
            ];
            return starterChatGpt.copyWith(name: layout.name, buttons: buttons);
          }
          return layout;
        })
        .toList(growable: true);
    if (!layouts.any((layout) => layout.id == 'codex')) {
      layouts.add(starterCodex);
    }
    for (final starterLayout in starter.layouts) {
      if (!layouts.any((layout) => layout.id == starterLayout.id)) {
        layouts.add(starterLayout);
      }
    }
    final legacyCodexApp = manifest.applicationById('codex');
    final applications = manifest.applications
        .where((application) => application.id != 'codex')
        .toList(growable: true);
    final chatGptIndex = applications.indexWhere(
      (application) => application.id == 'chatgpt',
    );
    if (legacyCodexApp != null && chatGptIndex >= 0) {
      final chatGpt = applications[chatGptIndex];
      applications[chatGptIndex] = chatGpt.copyWith(
        detected: chatGpt.detected || legacyCodexApp.detected,
        running: chatGpt.running || legacyCodexApp.running,
        foreground: chatGpt.foreground || legacyCodexApp.foreground,
        executable: 'ChatGPT',
      );
    }
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
      activatedApplicationId: manifest.activatedApplicationId == 'codex'
          ? 'chatgpt'
          : manifest.activatedApplicationId,
      profiles: profiles,
      currentProfileId: currentProfileId,
    );
  }

  static DesktopManifest _applyPlatformDefaults(
    DesktopManifest manifest,
    DesktopManifest original,
  ) {
    if (!Platform.isMacOS) return manifest;
    const layoutsWithMacDefaults = {
      'app.edge',
      'app.firefox',
      'app.safari',
      'app.zoom',
    };
    final layouts = manifest.layouts
        .map((layout) {
          final originalLayout = original.layoutById(layout.id);
          final defaultEdgeLayoutNeedsMacKeys =
              layout.id == 'app.edge' && _hasDefaultEdgeNavigation(layout);
          if (!layoutsWithMacDefaults.contains(layout.id) ||
              (originalLayout != null && !defaultEdgeLayoutNeedsMacKeys)) {
            return layout;
          }
          return layout.copyWith(
            buttons: layout.buttons
                .map((button) {
                  final keys = switch (button.id) {
                    'edge.back' ||
                    'firefox.back' ||
                    'safari.back' => const ['PRIMARY', '['],
                    'firefox.forward' ||
                    'edge.forward' ||
                    'safari.forward' => const ['PRIMARY', ']'],
                    'zoom.mute' => const ['PRIMARY', 'SHIFT', 'A'],
                    'zoom.video' => const ['PRIMARY', 'SHIFT', 'V'],
                    'zoom.hand' => const ['ALT', 'Y'],
                    'zoom.chat' => const ['PRIMARY', 'SHIFT', 'H'],
                    _ => button.shortcut,
                  };
                  return button.copyWith(shortcut: keys);
                })
                .toList(growable: false),
          );
        })
        .toList(growable: false);
    return manifest.copyWith(layouts: layouts);
  }

  static bool _hasDefaultEdgeNavigation(RemoteShortcutLayout layout) {
    final back = layout.buttons
        .where((button) => button.id == 'edge.back')
        .toList(growable: false);
    final forward = layout.buttons
        .where((button) => button.id == 'edge.forward')
        .toList(growable: false);
    return back.length == 1 &&
        forward.length == 1 &&
        back.single.shortcut.join(',') == 'ALT,LEFT' &&
        forward.single.shortcut.join(',') == 'ALT,RIGHT';
  }

  static bool _sameKeys(List<String> left, List<String> right) =>
      left.length == right.length &&
      List.generate(
        left.length,
        (index) => left[index] == right[index],
      ).every((matches) => matches);

  static String _newComputerId() {
    final random = Random.secure();
    const hex = '0123456789abcdef';
    return List.generate(32, (_) => hex[random.nextInt(hex.length)]).join();
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
        final requestedButtonId = request.buttonId ?? '';
        final canonicalButtonId = _canonicalLegacyCodexButtonId(
          requestedButtonId,
        );
        final button = manifest.buttonById(canonicalButtonId);
        if (button == null) throw const FormatException('Unknown button');
        final vibeAppId = _vibeAppForButton(button.id);
        final managedAppId =
            vibeAppId ?? _managedAppForButton(button, _manifest);
        if (managedAppId != null) {
          await _serializeManagedAction(() async {
            final app = _manifest.applicationById(managedAppId);
            if (app == null) throw StateError('The app is not configured');
            if (!button.enabled) throw StateError('Shortcut is disabled');
            final allowedPasswordManager =
                managedAppId == 'chrome' &&
                button.id == 'chrome.passwordManager' &&
                button.targetType == RemoteTargetType.openUrl &&
                button.target == 'https://passwords.google.com/';
            final allowedChatGptVoice =
                managedAppId == 'chatgpt' &&
                button.id == 'chatgpt.codex.voice' &&
                button.targetType == RemoteTargetType.voiceInput;
            if (button.targetType != RemoteTargetType.keyboardShortcut &&
                button.targetType != RemoteTargetType.system &&
                !allowedPasswordManager &&
                !allowedChatGptVoice) {
              throw const FormatException(
                'Managed app actions must use a Desktop-approved action',
              );
            }
            if (!await _isLiveForeground(app)) {
              throw StateError(
                'Switch to ${app.name} before using this shortcut',
              );
            }
            await actions.executeButton(
              button,
              _manifest,
              expectedAppId: managedAppId,
            );
          });
        } else {
          await actions.executeButton(button, _manifest);
        }
      case RemoteActionKind.launchApplication:
        if (!_manifest.settings.autoLaunchApps) {
          throw StateError('Automatic app launching is disabled');
        }
        final requestedAppId = request.applicationId ?? '';
        final app = _manifest.applicationById(
          requestedAppId == 'codex' ? 'chatgpt' : requestedAppId,
        );
        if (app == null) throw const FormatException('Unknown application');
        if (!_isManagedLaunchApp(app.id) && !_isStarterLaunchApp(app.id)) {
          throw const FormatException('Unsupported application');
        }
        if (!app.detected) {
          throw StateError('${app.name} is not installed on this computer');
        }
        await _serializeManagedAction(() async {
          await actions.activateApplication(app);
          await _publishActivatedApplication(app.id);
          final source = discovery;
          if (source is PlatformApplicationDiscovery) {
            source.preferredForegroundAppId = app.id;
          }
        });
      case RemoteActionKind.switchProfile:
        await switchProfile(request.profileId ?? '');
    }
  }

  static String _canonicalLegacyCodexButtonId(String id) {
    if (!id.startsWith('codex.')) return id;
    final action = id.substring('codex.'.length);
    return switch (action) {
      'newChat' => 'chatgpt.newChat',
      'previousConversation' => 'chatgpt.codex.previousChat',
      'nextConversation' => 'chatgpt.codex.nextChat',
      'findInChat' => 'chatgpt.find',
      'sidebar' => 'chatgpt.sidebar',
      _ => 'chatgpt.codex.$action',
    };
  }

  static String _canonicalLegacyVibeCodexButtonId(String id) {
    if (!id.startsWith('vibe.codex.')) return id;
    final action = id.substring('vibe.codex.'.length);
    return action == 'newChat' ? 'chatgpt.newChat' : 'chatgpt.codex.$action';
  }

  static RemoteShortcutButton _copyButtonWithId(
    RemoteShortcutButton button,
    String id,
  ) => RemoteShortcutButton(
    id: id,
    name: button.name,
    icon: button.icon,
    targetType: button.targetType,
    shortcut: button.shortcut,
    target: button.target,
    description: button.description,
    enabled: button.enabled,
  );

  Future<bool> _isLiveForeground(RemoteApplication app) async {
    final probe = foregroundProbe;
    if (probe != null) return probe(app);
    final source = discovery;
    if (source is PlatformApplicationDiscovery) {
      return source.isForeground(app, applications: _manifest.applications);
    }
    return false;
  }

  Future<void> _serializeManagedAction(Future<void> Function() action) async {
    if (_managedActionRunning) {
      throw StateError('Another app action is in progress');
    }
    _managedActionRunning = true;
    _applicationRefreshGeneration++;
    try {
      await action();
    } finally {
      _managedActionRunning = false;
      _applicationRefreshGeneration++;
    }
  }

  Future<void> _publishActivatedApplication(String appId) async {
    final updatedApps = _manifest.applications
        .map(
          (app) => app.copyWith(
            running: app.running || app.id == appId,
            foreground: app.id == appId,
          ),
        )
        .toList(growable: false);
    final next = _withApplications(
      updatedApps,
    ).copyWith(activatedApplicationId: appId);
    if (jsonEncode(next.toJson()) == jsonEncode(_manifest.toJson())) return;
    await _commit(next);
  }

  static const _managedApps = {
    'chrome',
    'edge',
    'firefox',
    'safari',
    'teams',
    'zoom',
    'chatgpt',
  };

  static const _managedLaunchApps = {
    ..._managedApps,
    'codex',
    'claude',
    'cursor',
  };

  static bool _isManagedLaunchApp(String id) => _managedLaunchApps.contains(id);

  static const _starterLaunchApps = {
    'photoshop',
    'illustrator',
    'vscode',
    'solidworks',
    'premiere',
    'appleMusic',
    'finder',
  };

  static bool _isStarterLaunchApp(String id) => _starterLaunchApps.contains(id);

  static String? _vibeAppForButton(String id) {
    for (final app in const ['codex', 'claude', 'cursor']) {
      if (id.startsWith('vibe.$app.')) return app;
    }
    return null;
  }

  static String? _managedAppForButton(
    RemoteShortcutButton button,
    DesktopManifest manifest,
  ) {
    for (final app in manifest.applications) {
      if (!_managedApps.contains(app.id)) continue;
      final layout = manifest.layoutById(app.layoutId);
      if (layout != null &&
          layout.buttons.any((item) => item.id == button.id)) {
        return app.id;
      }
    }
    return null;
  }

  Future<void> executeLegacy(Map<String, Object?> request) =>
      actions.executeLegacy(request);

  Future<void> applyPointerInputs(List<PointerInput> inputs) =>
      actions.applyPointerInputs(inputs);

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
