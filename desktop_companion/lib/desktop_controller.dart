import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'app_library/app_library.dart';
import 'app_library_bundle.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_actions.dart';
import 'app_icon_service.dart';
import 'installed_app_registry.dart';
import 'installed_app_discovery.dart';
import 'desktop_native_backend.dart';
import 'windows_desktop_backend.dart';
import 'icons/builtin_icon_catalog.g.dart';

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

abstract interface class LauncherKeyStore {
  Future<List<String?>> load();
  Future<void> save(List<String?> appIds);
}

class SharedPreferencesLauncherKeyStore implements LauncherKeyStore {
  SharedPreferencesLauncherKeyStore({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();

  static const storageKey = 'lumiakeys.desktop.launcher_keys.v1';
  final SharedPreferencesAsync preferences;

  @override
  Future<List<String?>> load() async {
    final values = await preferences.getStringList(storageKey);
    if (values == null ||
        (values.length != 8 && values.length != launcherSlotCount)) {
      return List<String?>.filled(launcherSlotCount, null);
    }
    return [
      ...values.map((value) => value.isEmpty ? null : value),
      ...List<String?>.filled(launcherSlotCount - values.length, null),
    ];
  }

  @override
  Future<void> save(List<String?> appIds) async {
    if (appIds.length != launcherSlotCount) {
      throw const FormatException('Launcher needs twelve keys');
    }
    await preferences.setStringList(
      storageKey,
      appIds.map((id) => id ?? '').toList(),
    );
  }
}

class MemoryLauncherKeyStore implements LauncherKeyStore {
  List<String?> value = List<String?>.filled(launcherSlotCount, null);

  @override
  Future<List<String?>> load() async => List<String?>.from(value);

  @override
  Future<void> save(List<String?> appIds) async =>
      value = List<String?>.from(appIds);
}

abstract interface class ApplicationDiscovery {
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps);
}

class PlatformApplicationDiscovery implements ApplicationDiscovery {
  PlatformApplicationDiscovery({
    NativeDesktopBackend? desktopBackend,
    WindowsDesktopBackend? windowsDesktopBackend,
    InstalledProcessRunner? runProcess,
    Map<String, String>? environment,
  }) : _environment = environment ?? Platform.environment,
       _desktopBackendOverride = desktopBackend,
       _windowsDesktopBackend =
           windowsDesktopBackend ??
           selectWindowsDesktopBackend(
             isWindows: Platform.isWindows,
             environment: environment ?? Platform.environment,
           ),
       _runProcess = runProcess ?? Process.run;

  final Map<String, String> _environment;
  final NativeDesktopBackend? _desktopBackendOverride;
  final WindowsDesktopBackend? _windowsDesktopBackend;
  late final NativeDesktopBackend? _desktopBackend =
      _desktopBackendOverride ??
      _windowsDesktopBackend ??
      selectNativeDesktopBackend(
        platform: hostDesktopTargetPlatform(),
        environment: _environment,
      );
  final InstalledProcessRunner _runProcess;
  WindowsRegistryInventory? _windowsRegistry;
  DateTime? _installedChecked;
  List<String> _cachedMacNames = [], _cachedWindowsNames = [];
  final Map<String, String?> _cachedExecutablePaths = {};
  void invalidateInstalledCache() {
    _installedChecked = null;
    _cachedExecutablePaths.clear();
  }

  // ChatGPT and Codex can share one desktop process. The controller updates
  // this after an explicit phone activation so subsequent probes retain the
  // panel the user asked to open.
  String? preferredForegroundAppId;

  static const _macOnlyApplicationIds = {'appleMusic', 'finder', 'safari'};
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async {
    final now = DateTime.now();
    if (_installedChecked == null ||
        now.difference(_installedChecked!) >= const Duration(seconds: 60)) {
      if (Platform.isMacOS) _cachedMacNames = await _macApplicationNames();
      if (Platform.isWindows) {
        final registry = await _readWindowsRegistry();
        _windowsRegistry = registry;
        _cachedWindowsNames = [
          if (registry != null)
            for (final name in registry.installedNames)
              ..._normalizedLines(name),
          ...await _windowsApplicationNames(shellOnly: registry != null),
        ];
      }
      _cachedExecutablePaths.clear();
      _installedChecked = now;
    }
    final installedMacApps = _cachedMacNames;
    final installedWindowsApps = _cachedWindowsNames;
    final snapshot = await _readDesktopProcesses();
    final runningProcesses =
        snapshot?.runningProcesses ?? await _runningProcessNames();
    final foregroundProcess = snapshot != null
        ? snapshot.foregroundProcess
        : await _legacyForegroundProcessName();
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
          if (!_cachedExecutablePaths.containsKey(executable)) {
            final result = await _runProcess('where.exe', [executable]);
            _cachedExecutablePaths[executable] = result.exitCode == 0
                ? result.stdout
                      .toString()
                      .split(RegExp(r'[\r\n]+'))
                      .first
                      .trim()
                : null;
          }
          final resolved = _cachedExecutablePaths[executable];
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
            detected:
                resolved != null ||
                _windowsRegistry?.findExecutable(executable) != null ||
                detectedByName ||
                running,
            running: running,
            foreground: foreground,
            executable: chatGptDetected
                ? 'ChatGPT.exe'
                : resolved ?? app.executable,
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
          final result = await _runProcess('which', [executable]);
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

  Future<WindowsRegistryInventory?> _readWindowsRegistry() async {
    final backend = _windowsDesktopBackend;
    if (backend == null || !Platform.isWindows) return null;
    try {
      return await backend.readRegistry().timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  Future<DesktopProcessSnapshot?> _readDesktopProcesses() async {
    final backend = _desktopBackend;
    if (backend == null) return null;
    try {
      return await backend.readProcesses().timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _windowsApplicationNames({
    required bool shellOnly,
  }) async {
    final result = await _runProcess('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      shellOnly
          ? r'Get-StartApps | Select-Object -ExpandProperty Name'
          : r'$paths = @('
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

  Future<List<String>> _runningProcessNames() async {
    ProcessResult result;
    if (Platform.isWindows) {
      result = await _runProcess('tasklist.exe', const ['/FO', 'CSV', '/NH']);
    } else {
      result = await _runProcess('ps', const ['-axo', 'comm=']);
    }
    if (result.exitCode != 0) return const [];
    return _normalizedLines(result.stdout);
  }

  /// Obtains only the process name needed to map the OS foreground window to a
  /// Desktop-owned application record. The value is never sent as a command or
  /// executable path to the phone.
  Future<String?> _foregroundProcessName() async {
    final backend = _desktopBackend;
    if (backend != null) {
      if (Platform.isLinux && !isLinuxX11Session(_environment)) return null;
      try {
        return await backend.readForegroundProcess().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        // The compatibility probe is read-only.
      }
    }
    return _legacyForegroundProcessName();
  }

  Future<String?> _legacyForegroundProcessName() async {
    ProcessResult result;
    if (Platform.isMacOS) {
      result = await _runProcess('/usr/bin/osascript', const [
        '-e',
        'tell application "System Events" to get name of first application process whose frontmost is true',
      ]);
    } else if (Platform.isWindows) {
      result = await _runProcess('powershell.exe', const [
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
      if (_desktopBackend != null && !isLinuxX11Session(_environment)) {
        return null;
      }
      final window = await _runProcess('xdotool', const [
        'getactivewindow',
        'getwindowpid',
      ]);
      if (window.exitCode != 0) return null;
      final pid = int.tryParse(window.stdout.toString().trim());
      if (pid == null) return null;
      result = await _runProcess('ps', ['-p', '$pid', '-o', 'comm=']);
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
    InstalledAppRegistry? installedRegistry,
    LauncherKeyStore? launcherKeyStore,
    this.foregroundProbe,
    String? libraryOperatingSystem,
  }) : libraryOperatingSystem =
           libraryOperatingSystem ??
           (Platform.isMacOS
               ? 'macos'
               : Platform.isWindows
               ? 'windows'
               : 'linux'),
       actions = actions ?? DesktopActions(),
       installedRegistry =
           installedRegistry ??
           (store is MemoryDesktopConfigStore
               ? InstalledAppRegistry()
               : InstalledAppRegistry(
                   discover: PlatformInstalledApplicationDiscovery().discover,
                   store: SharedPreferencesInstalledRegistryStore(),
                 )),
       discovery = discovery ?? PlatformApplicationDiscovery(),
       launcherKeyStore =
           launcherKeyStore ??
           (store is MemoryDesktopConfigStore
               ? MemoryLauncherKeyStore()
               : SharedPreferencesLauncherKeyStore()) {
    this.actions.registeredTargetResolver = this.installedRegistry.resolve;
    this.actions.installedLaunchAuthorizer = (id) =>
        _installedLaunchAllowed(id) && launcherAppIds.contains(id);
    this.actions.installedButtonLaunchAuthorizer = (id, buttonId) {
      final button = _manifest.buttonById(buttonId);
      return _installedLaunchAllowed(id) &&
          button != null &&
          button.enabled &&
          button.targetType == RemoteTargetType.launchApplication &&
          button.target == id;
    };
  }

  bool _installedLaunchAllowed(String id) {
    final app = _manifest.applicationById(id);
    return isInstalledApplicationId(id) &&
        _manifest.settings.autoLaunchApps &&
        app != null &&
        app.launchOnly &&
        app.detected &&
        installedRegistry.resolve(id) != null;
  }

  final String libraryOperatingSystem;
  final DesktopConfigStore store;
  final DesktopActions actions;
  final ApplicationDiscovery discovery;
  final InstalledAppRegistry installedRegistry;
  final LauncherKeyStore launcherKeyStore;
  final Future<bool> Function(RemoteApplication)? foregroundProbe;
  bool _managedActionRunning = false;
  int _applicationRefreshGeneration = 0;

  DesktopManifest _manifest = DesktopManifest.regularStarter();
  bool _loading = true;
  String? _error;
  String? _connectedPhone;
  int _selectedSection = 0;
  bool _initialized = false;
  bool _configurationReady = false;
  bool _refreshingApplications = false;
  Timer? _applicationMonitor;
  Timer? _installedApplicationMonitor;
  bool _installedRefreshBusy = false;
  Future<void> _launcherSaveQueue = Future<void>.value();
  Future<void> _manifestSaveQueue = Future<void>.value();

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
      .where(
        (app) => !app.launchOnly && (Platform.isMacOS || app.id != 'safari'),
      )
      .toList(growable: false);
  bool get loading => _loading;
  String? get error => _error;
  String? get installedApplicationsError => installedRegistry.error;
  String? get connectedPhone => _connectedPhone;
  int get selectedSection => _selectedSection;
  List<String?> get launcherAppIds =>
      List.unmodifiable(_manifest.launcherApplicationIds);
  List<RemoteApplication> get launcherApplications => _manifest.applications
      .where((app) => app.detected || launcherAppIds.contains(app.id))
      .toList(growable: false);
  RemoteApplication? get foregroundApplication =>
      _manifest.applications.cast<RemoteApplication?>().firstWhere(
        (application) => application?.foreground == true,
        orElse: () => null,
      );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final loaded = await store.load() ?? DesktopManifest.regularStarter();
      _manifest = _applyRegularDefaults(_upgradeManifest(loaded), loaded);
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(_manifest.computerId ?? '')) {
        _manifest = _manifest.copyWith(computerId: _newComputerId());
      }
      _manifest = _applyPlatformDefaults(_manifest, loaded);
      try {
        final storedLauncherIds = loaded.hasLauncherConfiguration
            ? loaded.launcherApplicationIds
            : await launcherKeyStore.load();
        final normalized =
            (storedLauncherIds.length == 8 ||
                storedLauncherIds.length == launcherSlotCount)
            ? storedLauncherIds
                  .map((id) {
                    final currentId = id == 'codex' ? 'chatgpt' : id;
                    return currentId != null &&
                            _manifest.applications.any(
                              (app) => app.id == currentId,
                            )
                        ? currentId
                        : null;
                  })
                  .toList(growable: false)
            : <String?>[];
        _manifest = _manifest.copyWith(
          launcherApplicationIds: [
            ...normalized,
            ...List<String?>.filled(
              launcherSlotCount - normalized.length,
              null,
            ),
          ],
        );
      } catch (error) {
        // A transient read failure is not an explicit empty configuration.
        // Leave durable preferences untouched so the next launch can recover.
        throw StateError(
          'Could not load the previous launcher configuration: $error',
        );
      }
      try {
        await installedRegistry.refresh();
      } catch (_) {
        /* Preserve existing configuration; registered launches fail closed. */
      }
      final apps = await discovery.refresh(
        _manifest.applications.where((app) => !app.launchOnly).toList(),
      );
      _manifest = _withInstalledApplications(apps);
      if (jsonEncode(_manifest.toJson()) != jsonEncode(loaded.toJson())) {
        _manifest = _manifest.copyWith(revision: loaded.revision + 1);
      }
      await store.save(_manifest);
      _configurationReady = true;
    } catch (error) {
      _error = '$error';
      _manifest = DesktopManifest.regularStarter();
    } finally {
      _loading = false;
      notifyListeners();
      if (_configurationReady && discovery is PlatformApplicationDiscovery) {
        _applicationMonitor = Timer.periodic(
          const Duration(seconds: 3),
          (_) => unawaited(_refreshRuntimeApplications()),
        );
        _installedApplicationMonitor = Timer.periodic(
          const Duration(seconds: 60),
          (_) => unawaited(refreshApplications(forceInstalled: false)),
        );
      }
    }
  }

  void selectSection(int index) {
    if (_selectedSection == index) return;
    _selectedSection = index;
    notifyListeners();
  }

  Future<void> assignLauncherApp(int index, String? appId) async {
    if (index < 0 || index >= launcherSlotCount) {
      throw RangeError.index(index, launcherAppIds, 'index');
    }
    if (appId != null &&
        !_manifest.applications.any((app) => app.id == appId)) {
      throw const FormatException('Unknown launcher application');
    }
    if (appId != null &&
        isInstalledApplicationId(appId) &&
        installedRegistry.resolve(appId) == null &&
        launcherAppIds[index] != appId) {
      throw const FormatException('This installed application is unavailable');
    }
    final operation = _launcherSaveQueue.then((_) async {
      await _commit((current) {
        final next = List<String?>.from(current.launcherApplicationIds)
          ..[index] = appId;
        return current.copyWith(launcherApplicationIds: next);
      });
    });
    _launcherSaveQueue = operation.catchError((_) {});
    await operation;
  }

  Future<void> launchLauncherApp(int index) async {
    if (index < 0 || index >= launcherSlotCount) {
      throw RangeError.index(index, launcherAppIds);
    }
    final appId = launcherAppIds[index];
    if (appId == null) throw StateError('Choose an app for this key first.');
    final app = _manifest.applicationById(appId);
    if (app == null) {
      throw const FormatException('This app is no longer configured.');
    }
    await executeRemote(RemoteActionRequest.launchApplication(app.id));
  }

  void recordConnectedPhone(String address) {
    if (_connectedPhone == address) return;
    _connectedPhone = address;
    notifyListeners();
  }

  Future<void> updateSettings(RemoteSettings settings) {
    final before = _manifest.settings;
    return _commit(
      (current) => current.copyWith(
        settings: current.settings.copyWith(
          enableAppsSync: settings.enableAppsSync != before.enableAppsSync
              ? settings.enableAppsSync
              : null,
          autoLaunchApps: settings.autoLaunchApps != before.autoLaunchApps
              ? settings.autoLaunchApps
              : null,
          syncIcons: settings.syncIcons != before.syncIcons
              ? settings.syncIcons
              : null,
        ),
      ),
    );
  }

  Future<void> updateButton(
    String layoutId,
    RemoteShortcutButton updated,
  ) async {
    await _commit((current) {
      if (current.profiles.any(
        (p) => p.isLibraryProfile && p.layoutId == layoutId,
      )) {
        _validateLibraryButton(updated);
      }
      final layouts = current.layouts
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
      return current.copyWith(layouts: layouts);
    });
  }

  Future<void> updateApplication(RemoteApplication updated) async {
    if (updated.launchOnly || isInstalledApplicationId(updated.id)) {
      throw const FormatException(
        'Installed applications are managed in the Launchpad picker',
      );
    }
    await _commit((current) {
      final apps = current.applications
          .map((app) => app.id == updated.id ? updated : app)
          .toList(growable: false);
      return current.copyWith(applications: apps);
    });
  }

  /// Installs reviewed keyboard defaults in the same manifest record as their
  /// canonical icon association. No app executable or launch slot is changed.
  Future<String> installAppLibrary(
    String appId,
    String libraryId, {
    String? replaceProfileId,
    AppLibraryBundle? bundle,
  }) async {
    final app = AppLibraryCatalog.builtin.appById(appId);
    final library = app?.libraryForOS(libraryOperatingSystem);
    if (bundle != null && bundle.app.id != appId) {
      throw const FormatException('Bundle App mismatch');
    }
    if (app == null ||
        app.id != appId ||
        library == null ||
        library.id != libraryId) {
      throw const FormatException(
        'This App library is not available for this computer OS.',
      );
    }
    late String installedId;
    await _commit((current) {
      final replacing = replaceProfileId == null
          ? null
          : current.profiles.where((p) => p.id == replaceProfileId).firstOrNull;
      if (replaceProfileId != null &&
          (replacing == null ||
              replacing.sourceAppId != app.id ||
              replacing.platform != libraryOperatingSystem)) {
        throw const FormatException(
          'Choose an existing library profile for this App and OS.',
        );
      }
      installedId = replacing?.id ?? 'library.${_newComputerId()}';
      final layoutId = replacing?.layoutId ?? installedId;
      final existing = replacing == null ? null : current.layoutById(layoutId);
      if (replacing != null &&
          (existing == null ||
              current.applications.any((a) => a.layoutId == layoutId) ||
              current.profiles.any(
                (p) => p.id != replacing.id && p.layoutId == layoutId,
              ))) {
        throw const FormatException(
          'This shared layout cannot be replaced. Add a copy instead.',
        );
      }
      final originals = <String, String>{};
      final freshById = <String, RemoteShortcutButton>{};
      final actionIds = <String, String>{};
      for (final action in library.actions) {
        final id = '$layoutId.${action.id}';
        final fresh = RemoteShortcutButton(
          id: id,
          name: action.title,
          icon: 'keyboard',
          targetType: RemoteTargetType.keyboardShortcut,
          shortcut: action.keys.map(canonicalKeyToLiteral).toList(),
          enabled: action.isConfigured,
          description: action.isConfigured
              ? ''
              : 'Configure this shortcut in Desktop before use.',
        );
        originals[action.id] = _libraryActionHash(fresh);
        freshById[id] = fresh;
        actionIds[id] = action.id;
      }
      final buttons = <RemoteShortcutButton>[];
      for (final prior in existing?.buttons ?? const <RemoteShortcutButton>[]) {
        final fresh = freshById.remove(prior.id);
        final baseline = replacing?.sourceActionHashes[actionIds[prior.id]];
        buttons.add(
          fresh != null &&
                  baseline != null &&
                  _libraryActionHash(prior) == baseline
              ? fresh
              : prior,
        );
      }
      for (final fresh in freshById.values) {
        // A missing action with an installed baseline was explicitly deleted.
        // Keep its deletion; retain existing order and append only new defaults.
        if (replacing?.sourceActionHashes.containsKey(actionIds[fresh.id]) ==
            true) {
          continue;
        }
        buttons.add(fresh);
      }
      final managed = current.applications
          .where(
            (a) => a.id == app.id && !a.launchOnly && _isManagedLaunchApp(a.id),
          )
          .firstOrNull;
      final priorIcon =
          replacing ??
          current.profiles
              .where(
                (p) => p.sourceAppId == app.id && p.sourceIconPngBase64 != null,
              )
              .firstOrNull;
      final iconBase64 = bundle == null
          ? priorIcon?.sourceIconPngBase64
          : base64Encode(bundle.pngBytes);
      final iconHash = bundle?.iconHash ?? priorIcon?.sourceIconSha256;
      if (!app.bundled && iconBase64 == null) {
        throw const FormatException(
          'Download and import this App bundle to install its icon and shortcuts together.',
        );
      }
      if (iconBase64 != null) {
        AppLibraryBundle.decode(
          utf8.encode(
            jsonEncode({
              'schemaVersion': 1,
              'app': app.toJson(),
              'icon': {
                'id': app.iconId,
                'sha256': iconHash,
                'pngBase64': iconBase64,
              },
            }),
          ),
        );
      }
      final profile = RemoteProfile(
        id: installedId,
        name: replacing?.name ?? '${app.name} · ${library.family}',
        layoutId: layoutId,
        platform: libraryOperatingSystem,
        applicationId: managed?.id,
        sourceAppId: app.id,
        sourceLibraryId: library.id,
        sourceLibraryVersion: library.version,
        sourceIconId: app.iconId,
        sourceActionHashes: Map.unmodifiable(originals),
        sourceIconPngBase64: iconBase64,
        sourceIconSha256: iconHash,
      );
      final layout = RemoteShortcutLayout(
        id: layoutId,
        name: replacing == null ? profile.name : existing!.name,
        kind: RemoteLayoutKind.application,
        buttons: buttons,
      );
      return current.copyWith(
        layouts: [
          for (final item in current.layouts)
            if (item.id != layoutId) item,
          layout,
        ],
        profiles: [
          for (final item in current.profiles)
            if (item.id != installedId) item,
          profile,
        ],
      );
    });
    return installedId;
  }

  static void _validateLibraryButton(RemoteShortcutButton button) {
    if (button.targetType != RemoteTargetType.keyboardShortcut ||
        button.target != null ||
        (button.enabled && button.shortcut.isEmpty)) {
      throw const FormatException(
        'App library profiles accept keyboard shortcuts only; assign keys before enabling.',
      );
    }
    if (button.shortcut.isEmpty) return;
    final keys = button.shortcut.map((k) => k.toUpperCase()).toList();
    const mods = {'CTRL', 'ALT', 'SHIFT', 'META', 'COMMAND', 'PRIMARY', 'WIN'};
    final normal = keys.where((k) => !mods.contains(k)).toList();
    if (keys.length > 5 ||
        keys.toSet().length != keys.length ||
        normal.length != 1 ||
        keys.last != normal.single ||
        !(isAppLibraryKey(normal.single) ||
            const {
              '[',
              ']',
              r'\',
              ';',
              "'",
              '`',
              ',',
              '.',
              '/',
              '-',
              '=',
              'PAGEUP',
              'PAGEDOWN',
            }.contains(normal.single))) {
      throw const FormatException(
        'Use one supported keyboard key with optional modifiers.',
      );
    }
  }

  static String _libraryActionHash(RemoteShortcutButton button) =>
      sha256.convert(utf8.encode(jsonEncode(button.toJson()))).toString();

  List<RemoteSidebarItem> get sidebarItems =>
      List.unmodifiable(_manifest.effectiveSidebarItems);
  List<RemoteSidebarItem> get sidebarCandidates => List.unmodifiable([
    for (final app in applicationsForCurrentPlatform)
      RemoteSidebarItem.application(app.id),
    for (final profile in _manifest.profiles.where(
      (p) => p.isLibraryProfile && p.platform == libraryOperatingSystem,
    ))
      RemoteSidebarItem.profile(profile.id),
  ]);
  String sidebarItemName(RemoteSidebarItem item) =>
      item.kind == RemoteSidebarKind.application
      ? _manifest.applicationById(item.id)?.name ?? item.id
      : _manifest.profiles.where((p) => p.id == item.id).firstOrNull?.name ??
            item.id;

  Future<void> setSidebarVisible(RemoteSidebarItem item, bool visible) =>
      _commit((current) {
        if (visible &&
            !sidebarCandidates.any((candidate) => candidate.key == item.key)) {
          throw const FormatException(
            'Choose a configured shortcut App or installed library profile.',
          );
        }
        final next = current.effectiveSidebarItems
            .where((candidate) => candidate.key != item.key)
            .toList();
        if (visible &&
            !current.effectiveSidebarItems.any(
              (candidate) => candidate.key == item.key,
            )) {
          next.add(item);
        } else if (visible) {
          return current;
        }
        return current.copyWith(sidebarItems: List.unmodifiable(next));
      });
  Future<void> moveSidebarItem(RemoteSidebarItem item, int delta) =>
      _commit((current) {
        if (delta != -1 && delta != 1) {
          throw const FormatException('Invalid sidebar move');
        }
        final next = current.effectiveSidebarItems.toList();
        final index = next.indexWhere((candidate) => candidate.key == item.key);
        if (index < 0 || index + delta < 0 || index + delta >= next.length) {
          return current;
        }
        final moving = next.removeAt(index);
        next.insert(index + delta, moving);
        return current.copyWith(sidebarItems: List.unmodifiable(next));
      });
  Future<void> restoreSidebarDefaults() =>
      _commit((current) => current.copyWith(clearSidebarConfiguration: true));

  Future<void> importShortcutLayouts(
    List<RemoteShortcutLayout> imported,
  ) async {
    if (imported.isEmpty) {
      throw const FormatException('No shortcut layouts to import');
    }
    await _commit((current) {
      final existingById = {
        for (final layout in current.layouts) layout.id: layout,
      };
      for (final layout in imported) {
        final existing = existingById[layout.id];
        if (current.profiles.any(
          (p) => p.isLibraryProfile && p.layoutId == layout.id,
        )) {
          for (final button in layout.buttons) {
            _validateLibraryButton(button);
          }
        }
        if (existing == null || existing.kind != layout.kind) {
          throw const FormatException(
            'Imported JSON contains an unknown shortcut layout',
          );
        }
        for (final button in layout.buttons) {
          if (button.targetType == RemoteTargetType.launchApplication &&
              current.applicationById(button.target ?? '') == null) {
            throw const FormatException(
              'Imported shortcut references an unknown application',
            );
          }
        }
      }
      final importedById = {for (final layout in imported) layout.id: layout};
      final importedChatGpt = importedById['chatgpt'];
      if (importedChatGpt != null) {
        final currentChatGpt = current.layoutById('chatgpt');
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
      final candidate = current.copyWith(
        layouts: current.layouts
            .map((layout) => importedById[layout.id] ?? layout)
            .toList(growable: false),
      );
      candidate.validate();
      return candidate;
    });
  }

  Future<void> refreshApplications({bool forceInstalled = true}) async {
    if (!_configurationReady || _installedRefreshBusy) return;
    _installedRefreshBusy = true;
    final generation = _applicationRefreshGeneration;
    try {
      try {
        await installedRegistry.refresh(force: forceInstalled);
      } catch (_) {
        /* Publish unavailable state without erasing saved slots. */
      }
      if (discovery case final PlatformApplicationDiscovery source) {
        source.invalidateInstalledCache();
      }
      final apps = await discovery.refresh(
        _manifest.applications.where((app) => !app.launchOnly).toList(),
      );
      await _commit(
        (current) =>
            generation == _applicationRefreshGeneration &&
                !_managedActionRunning
            ? _withInstalledApplications(apps, base: current)
            : current,
      );
      _error = null;
    } catch (error) {
      _error = 'App discovery failed: $error';
      notifyListeners();
    } finally {
      _installedRefreshBusy = false;
    }
  }

  Future<void> addInstalledApplication(InstalledLaunchTarget target) async {
    if (!_configurationReady) {
      throw StateError('Desktop configuration is not ready');
    }
    await installedRegistry.addManual(target);
    await _commit(
      (current) => _withInstalledApplications(
        current.applications.where((app) => !app.launchOnly).toList(),
        base: current,
      ),
    );
  }

  Future<void> removeManualApplication(String id) async {
    await installedRegistry.removeManual(id);
    await _commit(
      (current) => _withInstalledApplications(
        current.applications.where((app) => !app.launchOnly).toList(),
        base: current,
      ),
    );
  }

  Future<void> _refreshRuntimeApplications() async {
    if (!_configurationReady ||
        _refreshingApplications ||
        _managedActionRunning) {
      return;
    }
    _refreshingApplications = true;
    final generation = _applicationRefreshGeneration;
    try {
      final apps = await discovery.refresh(
        _manifest.applications.where((app) => !app.launchOnly).toList(),
      );
      final projected = _withInstalledApplications(apps).applications;
      if (generation == _applicationRefreshGeneration &&
          !_managedActionRunning &&
          !_sameApplications(projected, _manifest.applications)) {
        await _commit(
          (current) =>
              generation == _applicationRefreshGeneration &&
                  !_managedActionRunning
              ? _withInstalledApplications(apps, base: current)
              : current,
        );
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
          a.foreground != b.foreground ||
          a.launchOnly != b.launchOnly) {
        return false;
      }
    }
    return true;
  }

  DesktopManifest _withInstalledApplications(
    List<RemoteApplication> legacy, {
    DesktopManifest? base,
  }) {
    final current = base ?? _manifest;
    final merged = <String, RemoteApplication>{
      for (final app in legacy)
        if (!app.launchOnly) app.id: app,
    };
    for (final previous in current.applications.where(
      (app) =>
          app.launchOnly && current.launcherApplicationIds.contains(app.id),
    )) {
      merged[previous.id] = previous.copyWith(
        icon: canonicalBuiltinIconId(previous.icon) ?? 'apps',
        detected: false,
        running: false,
        foreground: false,
      );
    }
    for (final target in installedRegistry.entries) {
      merged[target.id] = RemoteApplication(
        id: target.id,
        name: target.name,
        icon: canonicalBuiltinIconId(target.iconKey ?? '') ?? 'apps',
        executable: 'Desktop-managed',
        layoutId: installedLaunchOnlyLayoutId,
        detected: target.available,
        launchOnly: true,
      );
    }
    final layouts = current.layouts;
    final shaped =
        merged.values.any((app) => app.launchOnly) &&
            !layouts.any((layout) => layout.id == installedLaunchOnlyLayoutId)
        ? current.copyWith(layouts: [...layouts, installedLaunchOnlyLayout])
        : current;
    return _withApplications(merged.values.toList(), base: shaped);
  }

  DesktopManifest _withApplications(
    List<RemoteApplication> apps, {
    DesktopManifest? base,
  }) {
    final current = base ?? _manifest;
    final previousForeground = current.applications
        .cast<RemoteApplication?>()
        .firstWhere((app) => app?.foreground == true, orElse: () => null)
        ?.id;
    final nextForeground = apps.cast<RemoteApplication?>().firstWhere(
      (application) => application?.foreground == true,
      orElse: () => null,
    );
    final activationChanged =
        nextForeground != null && nextForeground.id != previousForeground;
    return current.copyWith(
      applications: apps,
      applicationActivationSequence: activationChanged
          ? current.applicationActivationSequence + 1
          : current.applicationActivationSequence,
      activatedApplicationId: activationChanged
          ? nextForeground.id
          : current.activatedApplicationId,
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

  /// Adopt compact defaults only for unedited boards. Preserve saved custom
  /// bindings, order and overflow, which the mobile UI exposes in pages.
  static DesktopManifest _applyRegularDefaults(
    DesktopManifest upgraded,
    DesktopManifest original,
  ) {
    final catalog = DesktopManifest.starter();
    final regular = DesktopManifest.regularStarter();
    bool same(RemoteShortcutLayout? left, RemoteShortcutLayout? right) =>
        left != null &&
        right != null &&
        jsonEncode(left.toJson()) == jsonEncode(right.toJson());
    return upgraded.copyWith(
      layouts: upgraded.layouts
          .map((layout) {
            final saved = original.layoutById(layout.id);
            if (saved == null ||
                _regularDefaultCandidates(
                  catalog.layoutById(layout.id),
                ).any((candidate) => same(saved, candidate)) ||
                _regularDefaultCandidates(
                  regular.layoutById(layout.id),
                ).any((candidate) => same(saved, candidate))) {
              return compactDesktopLayout(layout);
            }
            // The first Chrome release shipped exactly these two defaults.
            // Only that exact untouched board adopts the current defaults.
            final oldChrome = catalog.layoutById('app.chrome')!;
            final hasLegacyReleaseMarker =
                original.applications.any((app) => app.id == 'codex') ||
                original.profiles.any(
                  (profile) => const {
                    'windows',
                    'mac',
                    'photoshop',
                    'vscode',
                    'premiere',
                  }.contains(profile.id),
                );
            if (hasLegacyReleaseMarker &&
                saved.id == oldChrome.id &&
                same(
                  saved,
                  oldChrome.copyWith(
                    buttons: oldChrome.buttons.take(2).toList(),
                  ),
                )) {
              return compactDesktopLayout(layout);
            }
            if (saved.id == 'chatgpt') {
              return _migrateCustomChatGpt(saved, layout, original, catalog);
            }
            return saved;
          })
          .toList(growable: false),
    );
  }

  /// Exact, previously shipped platform defaults only: a single edited name,
  /// binding or order keeps the board outside this migration allowlist.
  static List<RemoteShortcutLayout> _regularDefaultCandidates(
    RemoteShortcutLayout? layout,
  ) {
    if (layout == null) return const [];
    final mac = layout.copyWith(
      buttons: layout.buttons.map((button) {
        final keys = switch (button.id) {
          'edge.back' ||
          'firefox.back' ||
          'safari.back' => const ['PRIMARY', '['],
          'edge.forward' ||
          'firefox.forward' ||
          'safari.forward' => const ['PRIMARY', ']'],
          'zoom.mute' => const ['PRIMARY', 'SHIFT', 'A'],
          'zoom.video' => const ['PRIMARY', 'SHIFT', 'V'],
          'zoom.hand' => const ['ALT', 'Y'],
          'zoom.chat' => const ['PRIMARY', 'SHIFT', 'H'],
          _ => button.shortcut,
        };
        return button.copyWith(shortcut: keys);
      }).toList(),
    );
    RemoteShortcutLayout native(
      RemoteShortcutLayout source,
      RemoteShortcutPlatform platform,
    ) => source.copyWith(
      buttons: source.buttons
          .map(
            (button) => button.copyWith(
              shortcut: resolvePrimaryShortcut(button.shortcut, platform),
            ),
          )
          .toList(),
    );
    return [
      layout,
      mac,
      native(layout, RemoteShortcutPlatform.apple),
      native(mac, RemoteShortcutPlatform.apple),
      native(layout, RemoteShortcutPlatform.windows),
    ];
  }

  static RemoteShortcutLayout _migrateCustomChatGpt(
    RemoteShortcutLayout saved,
    RemoteShortcutLayout upgraded,
    DesktopManifest original,
    DesktopManifest catalog,
  ) {
    final upgradedById = {
      for (final button in upgraded.buttons) button.id: button,
    };
    final defaultsById = {
      for (final button in catalog.layoutById('chatgpt')!.buttons)
        button.id: button,
    };
    final buttons = <RemoteShortcutButton>[];
    final seen = <String>{};
    for (final button in saved.buttons) {
      final id = button.id == 'chatgpt.codex.sidebar'
          ? 'chatgpt.sidebar'
          : button.id;
      if (!seen.add(id)) {
        continue;
      }
      final unchangedSidebar =
          id == 'chatgpt.sidebar' &&
          jsonEncode(button.toJson()) == jsonEncode(defaultsById[id]?.toJson());
      buttons.add(
        id != button.id || unchangedSidebar
            ? upgradedById[id] ?? _copyButtonWithId(button, id)
            : button,
      );
    }
    // Consolidation may have to retain edits from the old separate Codex
    // boards. Append only actual user edits, never re-add removed defaults.
    for (final sourceId in const ['codex', 'vibe.codex']) {
      final source = original.layoutById(sourceId);
      final defaults = {
        for (final button in catalog.layoutById(sourceId)!.buttons)
          button.id: button,
      };
      for (final button in source?.buttons ?? const <RemoteShortcutButton>[]) {
        if (jsonEncode(button.toJson()) ==
            jsonEncode(defaults[button.id]?.toJson())) {
          continue;
        }
        final id = sourceId == 'codex'
            ? _canonicalLegacyCodexButtonId(button.id)
            : _canonicalLegacyVibeCodexButtonId(button.id);
        if (id == button.id) {
          // A custom globally unique ID remains on its original saved board.
          continue;
        }
        final index = buttons.indexWhere((current) => current.id == id);
        final migrated = _copyButtonWithId(button, id);
        if (index == -1) {
          seen.add(id);
          buttons.add(migrated);
        } else if (jsonEncode(buttons[index].toJson()) ==
            jsonEncode(defaultsById[id]?.toJson())) {
          buttons[index] = migrated;
        }
      }
    }
    return saved.copyWith(buttons: buttons);
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
    await _commit((current) => current.copyWith(currentProfileId: profileId));
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
        final libraryProfile = _libraryProfileForButton(button);
        if (libraryProfile != null &&
            (button.targetType != RemoteTargetType.keyboardShortcut ||
                button.shortcut.isEmpty)) {
          throw const FormatException(
            'Library profiles permit configured keyboard shortcuts only',
          );
        }
        final vibeAppId = _vibeAppForButton(button.id);
        final managedAppId =
            vibeAppId ??
            libraryProfile?.applicationId ??
            _managedAppForButton(button, _manifest);
        if (managedAppId != null) {
          await _serializeManagedAction(() async {
            final app = _manifest.applicationById(managedAppId);
            if (app == null || app.launchOnly || !_isManagedLaunchApp(app.id)) {
              throw StateError('The app is not configured for managed input');
            }
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
        if (app.launchOnly) {
          if (!isInstalledApplicationId(app.id) ||
              !launcherAppIds.contains(app.id) ||
              !app.detected ||
              installedRegistry.resolve(app.id) == null) {
            throw const FormatException(
              'Installed application is not configured or is unavailable',
            );
          }
          await _serializeManagedAction(
            () => actions.activateInstalledApplication(app.id),
          );
          // OS acceptance is not proof of foreground state and does not grant
          // this launch-only app any managed shortcut/injection capability.
          return;
        }
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
    await _commit((current) {
      final updatedApps = current.applications
          .map(
            (app) => app.copyWith(
              running: app.running || app.id == appId,
              foreground: app.id == appId,
            ),
          )
          .toList(growable: false);
      return current.copyWith(
        applications: updatedApps,
        activatedApplicationId: appId,
        applicationActivationSequence:
            current.applicationActivationSequence + 1,
      );
    });
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

  RemoteProfile? _libraryProfileForButton(RemoteShortcutButton button) {
    final profiles = _manifest.profiles.where(
      (p) =>
          p.isLibraryProfile &&
          (_manifest
                  .layoutById(p.layoutId)
                  ?.buttons
                  .any((b) => b.id == button.id) ??
              false),
    );
    if (profiles.isEmpty) return null;
    final profile = profiles.first;
    if (profile.platform != libraryOperatingSystem) {
      throw StateError('This library belongs to a different computer OS');
    }
    if (profile.applicationId != null &&
        (profile.applicationId != profile.sourceAppId ||
            !_isManagedLaunchApp(profile.applicationId!))) {
      throw const FormatException('Invalid managed library binding');
    }
    // Namespace changes cannot remove a known application's foreground guard.
    if (profile.applicationId == null &&
        _isManagedLaunchApp(profile.sourceAppId!)) {
      throw StateError(
        'The managed App is unavailable. Install its Desktop application before using this library.',
      );
    }
    return profile;
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

  Future<void> executeLegacy(Map<String, Object?> request) {
    if (request['kind'] == 'launch') {
      final id = request['target'];
      if (id is! String ||
          request.keys.any((key) => key != 'kind' && key != 'target') ||
          _manifest.applicationById(id) == null) {
        throw const FormatException(
          'Legacy application launch requires a registered application ID',
        );
      }
      return executeRemote(RemoteActionRequest.launchApplication(id));
    }
    return actions.executeLegacy(request);
  }

  Future<void> applyPointerInputs(List<PointerInput> inputs) =>
      actions.applyPointerInputs(inputs);

  Future<Uint8List?> applicationIcon(String appId) async {
    final dynamic = isInstalledApplicationId(appId);
    if ((!remoteApplicationIconAppIds.contains(appId) && !dynamic) ||
        (dynamic &&
            (!launcherAppIds.contains(appId) ||
                installedRegistry.resolve(appId) == null)) ||
        !_manifest.settings.enableAppsSync ||
        !_manifest.settings.syncIcons) {
      return null;
    }
    final app = _manifest.applicationById(appId);
    if (app == null || !app.detected) return null;
    try {
      final bytes = await actions
          .getApplicationIcon(app)
          .timeout(const Duration(seconds: 4));
      if (!_manifest.settings.enableAppsSync ||
          !_manifest.settings.syncIcons ||
          (dynamic &&
              (!launcherAppIds.contains(appId) ||
                  installedRegistry.resolve(appId) == null)) ||
          _manifest.applicationById(appId)?.detected != true) {
        return null;
      }
      return bytes != null && validApplicationIconPng(bytes) ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _commit(
    DesktopManifest Function(DesktopManifest current) update,
  ) async {
    if (!_configurationReady) {
      throw StateError(
        'Desktop configuration could not be loaded. Restart Desktop to retry before editing saved settings.',
      );
    }
    final operation = _manifestSaveQueue.then((_) async {
      final proposed = update(_manifest);
      bool referenceExists(DesktopManifest manifest, RemoteSidebarItem item) =>
          item.kind == RemoteSidebarKind.application
          ? manifest.applications.any(
              (app) => app.id == item.id && !app.launchOnly,
            )
          : manifest.profiles.any(
              (profile) => profile.id == item.id && profile.isLibraryProfile,
            );
      // Delete a previously valid target and its reference in one atomic record.
      // Newly supplied invalid references still fail strict validation.
      final revised =
          (proposed.sidebarItems == null
                  ? proposed
                  : proposed.copyWith(
                      sidebarItems: proposed.sidebarItems!
                          .where(
                            (item) =>
                                referenceExists(proposed, item) ||
                                !referenceExists(_manifest, item),
                          )
                          .toList(growable: false),
                    ))
              .copyWith(revision: _manifest.revision + 1);
      revised.validate();
      try {
        // Slots and revision are one atomic durable record. The old separate
        // key store is migration input only and can never resurrect clears.
        await store.save(revised);
        _manifest = revised;
        _error = null;
      } catch (error) {
        // A storage implementation can report failure after committing its
        // atomic record. Reconcile the actual durable result before reporting.
        try {
          final durable = await store.load();
          if (durable != null) {
            durable.validate();
            _manifest = durable;
          }
        } catch (_) {
          /* Keep the last confirmed in-memory snapshot. */
        }
        _error = 'Could not save Desktop settings: $error';
        notifyListeners();
        rethrow;
      }
      notifyListeners();
    });
    _manifestSaveQueue = operation.catchError((_) {});
    await operation;
  }

  @override
  void dispose() {
    _applicationMonitor?.cancel();
    _installedApplicationMonitor?.cancel();
    super.dispose();
  }
}
