import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'installed_app_launcher.dart';
import 'installed_app_registry.dart';
import 'windows_desktop_backend.dart';

/// Reads an installed app's local icon. This never resolves a URL or accepts
/// arbitrary executable names from remote actions; `application.executable`
/// comes from the desktop-owned manifest.
class NativeAppIconService {
  NativeAppIconService({
    MethodChannel? channel,
    this.platformOverride,
    Map<String, String>? environment,
    this.timeout = const Duration(seconds: 3),
    this.processRunner,
    this.linuxDesktopDirectories,
    this.linuxIconDirectories,
    WindowsDesktopBackend? windowsDesktopBackend,
    this.registeredTargetResolver,
    this.installedChannel,
    DateTime Function()? now,
  }) : channel = channel ?? const MethodChannel('lumiakeys/app_icon'),
       environment = environment ?? Platform.environment,
       _windowsDesktopBackend =
           windowsDesktopBackend ??
           (processRunner != null
               ? null
               : selectWindowsDesktopBackend(
                   isWindows:
                       (platformOverride ?? defaultTargetPlatform) ==
                       TargetPlatform.windows,
                   environment: environment ?? Platform.environment,
                 )),
       _now = now ?? DateTime.now;

  static const supportedAppIds = <String>{
    'codex',
    'chatgpt',
    'claude',
    'cursor',
    'chrome',
    'edge',
    'firefox',
    'safari',
    'teams',
    'zoom',
    'photoshop',
    'illustrator',
    'vscode',
    'solidworks',
    'premiere',
    'appleMusic',
    'finder',
  };

  final MethodChannel channel;
  final TargetPlatform? platformOverride;
  final Map<String, String> environment;
  final Duration timeout;
  final Future<ProcessResult> Function(String, List<String>, Duration)?
  processRunner;
  final List<String>? linuxDesktopDirectories;
  final List<String>? linuxIconDirectories;
  InstalledTargetResolver? registeredTargetResolver;
  final MethodChannel? installedChannel;
  final WindowsDesktopBackend? _windowsDesktopBackend;
  late final InstalledApplicationLauncher _installedLauncher =
      InstalledApplicationLauncher(
        resolve: (id) => registeredTargetResolver?.call(id),
        channel: installedChannel,
        platformOverride: platformOverride,
        timeout: timeout,
      );
  final DateTime Function() _now;
  final Map<String, (DateTime, Uint8List?)> _cache = {};
  final Map<String, Future<Uint8List?>> _pending = {};

  Future<Uint8List?> getNativeIcon(RemoteApplication application) async {
    final registered = application.launchOnly
        ? _installedLauncher.registeredTarget(application.id)
        : null;
    if (application.launchOnly && registered == null ||
        !application.launchOnly &&
            (!supportedAppIds.contains(application.id) ||
                application.executable.length > 1024 ||
                application.executable.codeUnits.any(
                  (unit) => unit < 32 || unit == 127,
                ))) {
      return null;
    }
    final key = registered == null
        ? '${application.id}\u0000${application.executable}'
        : '${registered.id}\u0000${registered.kind.name}\u0000${registered.identity}\u0000${registered.locator}';
    final cached = _cache[key];
    if (cached != null && _now().isBefore(cached.$1)) return cached.$2;
    return _pending[key] ??= _extract(application)
        .then((bytes) {
          _cache[key] = (
            _now().add(
              bytes == null
                  ? const Duration(seconds: 30)
                  : const Duration(minutes: 5),
            ),
            bytes,
          );
          if (_cache.length > 128) {
            _cache.remove(_cache.keys.first);
          }
          return bytes;
        })
        .whenComplete(() {
          _pending.remove(key);
        });
  }

  Future<Uint8List?> _extract(RemoteApplication application) async {
    try {
      final platform = platformOverride ?? defaultTargetPlatform;
      final bytes =
          await (application.launchOnly
                  ? _installedLauncher.icon(application.id)
                  : switch (platform) {
                      TargetPlatform.linux => _linuxDesktopIcon(application),
                      TargetPlatform.windows => _windowsNativeIcon(
                        application.id,
                      ),
                      TargetPlatform.macOS =>
                        channel.invokeMethod<Uint8List>('get', {
                          'appId': application.id,
                          'executable': application.executable,
                        }),
                      _ => Future<Uint8List?>.value(),
                    })
              .timeout(timeout);
      return bytes != null && validApplicationIconPng(bytes) ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  static String windowsIconCommand(String appId) {
    if (!supportedAppIds.contains(appId)) {
      throw const FormatException('Unknown icon application');
    }
    const script = r'''
$executables = switch ($appId) {
  'codex' { @('Codex.exe') }
  'chatgpt' { @('ChatGPT.exe') }
  'claude' { @('Claude.exe') }
  'cursor' { @('Cursor.exe') }
  'chrome' { @('chrome.exe') }
  'edge' { @('msedge.exe') }
  'firefox' { @('firefox.exe') }
  'teams' { @('ms-teams.exe', 'Teams.exe') }
  'zoom' { @('Zoom.exe') }
  'photoshop' { @('Photoshop.exe') }
  'illustrator' { @('Illustrator.exe') }
  'vscode' { @('Code.exe') }
  'solidworks' { @('SLDWORKS.exe') }
  'premiere' { @('Adobe Premiere Pro.exe') }
  default { @() }
}
$path = $null
foreach ($exe in $executables) {
  $keys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$exe",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\$exe",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$exe"
  )
  foreach ($key in $keys) {
    if (Test-Path $key) {
      $candidate = (Get-Item $key).GetValue('')
      if ($candidate -and (Test-Path $candidate)) { $path = $candidate; break }
    }
  }
  if (-not $path) {
    $command = Get-Command $exe -ErrorAction SilentlyContinue
    if ($command) { $path = $command.Source }
  }
  if ($path) { break }
}
if (-not $path) { exit 2 }
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
if (-not $icon) { exit 3 }
$bitmap = $icon.ToBitmap()
$stream = New-Object System.IO.MemoryStream
$bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
if ($stream.Length -gt 65536) { exit 4 }
[Convert]::ToBase64String($stream.ToArray())
$stream.Dispose(); $bitmap.Dispose(); $icon.Dispose()
''';
    return '''
& {
param([string]\$appId)
$script
} '$appId'
''';
  }

  Future<Uint8List?> _windowsNativeIcon(String appId) async {
    final backend = _windowsDesktopBackend;
    final names = _windowsIconExecutables[appId];
    if (backend != null && names != null) {
      try {
        final inventory = await backend.readRegistry().timeout(timeout);
        for (final name in names) {
          final entry = inventory.findExecutable(name);
          if (entry == null) continue;
          final target = InstalledLaunchTarget.discovered(
            name: entry.name,
            kind: InstalledLaunchKind.windowsExecutable,
            identity: 'apppath:${entry.path.toLowerCase()}',
            locator: entry.path,
            executablePath: entry.path,
          );
          final launcher = InstalledApplicationLauncher(
            resolve: (id) => target.id == id ? target : null,
            channel: installedChannel,
            platformOverride: TargetPlatform.windows,
            timeout: timeout,
          );
          final bytes = await launcher.icon(target.id);
          if (bytes != null && validApplicationIconPng(bytes)) return bytes;
        }
      } catch (_) {
        // Existing read-only artwork lookup also covers non-registry apps.
      }
    }
    try {
      final result =
          await (processRunner ?? runBoundedDesktopProcess)('powershell.exe', [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-Command',
            windowsIconCommand(appId),
          ], timeout);
      if (result.exitCode != 0) return null;
      final encoded = '${result.stdout}'.trim();
      if (encoded.isEmpty || encoded.length > 88 * 1024) return null;
      final bytes = base64Decode(encoded);
      return validApplicationIconPng(bytes) ? bytes : null;
    } on ProcessException {
      return null;
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static const _windowsIconExecutables = <String, List<String>>{
    'codex': ['Codex.exe'],
    'chatgpt': ['ChatGPT.exe'],
    'claude': ['Claude.exe'],
    'cursor': ['Cursor.exe'],
    'chrome': ['chrome.exe'],
    'edge': ['msedge.exe'],
    'firefox': ['firefox.exe'],
    'teams': ['ms-teams.exe', 'Teams.exe'],
    'zoom': ['Zoom.exe'],
    'photoshop': ['Photoshop.exe'],
    'illustrator': ['Illustrator.exe'],
    'vscode': ['Code.exe'],
    'solidworks': ['SLDWORKS.exe'],
    'premiere': ['Adobe Premiere Pro.exe'],
  };

  Future<Uint8List?> _linuxDesktopIcon(RemoteApplication application) async {
    final aliases = _linuxAliases(application.id, application.executable);
    final roots =
        linuxDesktopDirectories ??
        <String>[
          if (environment['HOME'] case final home?)
            '$home/.local/share/applications',
          '/usr/local/share/applications',
          '/usr/share/applications',
        ];
    final iconNames = <String>[];
    var visited = 0;
    final deadline = _now().add(timeout);
    for (final root in roots) {
      final directory = Directory(root);
      if (!await directory.exists()) continue;
      await for (final entry in directory.list(followLinks: false)) {
        if (++visited > 512 || _now().isAfter(deadline)) return null;
        if (entry is! File || !entry.path.endsWith('.desktop')) continue;
        if (await entry.length() > 256 * 1024) continue;
        final contents = await entry.readAsString().catchError((_) => '');
        final desktop = _desktopEntry(contents);
        if (desktop == null) continue;
        final name = (desktop['Name'] ?? '').toLowerCase();
        final exec = (desktop['Exec'] ?? '')
            .split(RegExp(r'\s+'))
            .first
            .replaceAll('"', '')
            .split('/')
            .last
            .toLowerCase();
        final file = entry.uri.pathSegments.last.toLowerCase();
        if (!aliases.any(
          (alias) =>
              name == alias ||
              exec == alias ||
              file == '$alias.desktop' ||
              file.endsWith('.$alias.desktop'),
        )) {
          continue;
        }
        final icon = desktop['Icon'];
        if (icon != null && icon.isNotEmpty) iconNames.add(icon);
      }
    }
    for (final name in iconNames) {
      final candidates = _linuxIconCandidates(name);
      for (final path in candidates) {
        final file = File(path);
        if (!await file.exists()) continue;
        if (await file.length() > 64 * 1024) continue;
        final bytes = await file.readAsBytes();
        if (validApplicationIconPng(bytes)) return bytes;
      }
    }
    return null;
  }

  static Map<String, String>? _desktopEntry(String contents) {
    var inEntry = false;
    final values = <String, String>{};
    for (final line in const LineSplitter().convert(contents)) {
      if (line.startsWith('[')) {
        if (inEntry) break;
        inEntry = line == '[Desktop Entry]';
      } else if (inEntry && !line.startsWith('#')) {
        final split = line.indexOf('=');
        if (split > 0) {
          values[line.substring(0, split)] = line.substring(split + 1);
        }
      }
    }
    return inEntry ? values : null;
  }

  static List<String> _linuxAliases(String id, String executable) {
    final alias = switch (id) {
      'codex' => const ['codex'],
      'chatgpt' => const ['chatgpt', 'openai chatgpt'],
      'vscode' => const ['visual studio code', 'vscode', 'code'],
      'chrome' => const ['google chrome', 'chrome'],
      'edge' => const ['microsoft edge', 'edge'],
      'firefox' => const ['firefox'],
      'claude' => const ['claude'],
      'cursor' => const ['cursor'],
      'teams' => const ['teams'],
      'zoom' => const ['zoom'],
      'photoshop' => const ['photoshop'],
      'illustrator' => const ['illustrator'],
      'premiere' => const ['premiere'],
      'solidworks' => const ['solidworks'],
      'safari' => const ['safari'],
      'appleMusic' => const ['music', 'apple music'],
      'finder' => const ['finder'],
      _ => const <String>[],
    };
    final executableName = executable.split('/').last.toLowerCase();
    return {...alias, if (executableName.isNotEmpty) executableName}.toList();
  }

  List<String> _linuxIconCandidates(String icon) {
    if (icon.contains('..') ||
        icon.contains('\\') ||
        icon.contains('://') ||
        icon.length > 1024) {
      return const [];
    }
    if (icon.startsWith('/')) {
      return [if (icon.toLowerCase().endsWith('.png')) icon];
    }
    final fileName = icon.toLowerCase().endsWith('.png') ? icon : '$icon.png';
    const sizes = [
      '512x512',
      '256x256',
      '128x128',
      '96x96',
      '64x64',
      '48x48',
      '32x32',
    ];
    final roots =
        linuxIconDirectories ??
        <String>[
          if (environment['HOME'] case final home?) '$home/.local/share/icons',
          '/usr/local/share/icons',
          '/usr/share/icons',
        ];
    return [
      ...roots.expand(
        (root) => sizes.map((size) => '$root/hicolor/$size/apps/$fileName'),
      ),
      ...roots.map((root) => '$root/hicolor/scalable/apps/$fileName'),
      '/usr/local/share/pixmaps/$fileName',
      '/usr/share/pixmaps/$fileName',
    ];
  }
}

/// Bound dimensions before decompressing, then reject malformed image data.
bool validApplicationIconPng(Uint8List bytes) {
  if (bytes.length < 33 ||
      bytes.length > 64 * 1024 ||
      !const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ].asMap().entries.every((entry) => bytes[entry.key] == entry.value) ||
      ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
    return false;
  }
  final header = ByteData.sublistView(bytes);
  final width = header.getUint32(16), height = header.getUint32(20);
  if (width < 1 || height < 1 || width > 512 || height > 512) return false;
  try {
    final decoded = img.decodePng(bytes);
    return decoded != null &&
        decoded.width == width &&
        decoded.height == height;
  } catch (_) {
    return false;
  }
}

Future<ProcessResult> runBoundedDesktopProcess(
  String executable,
  List<String> arguments,
  Duration timeout,
) async {
  final process = await Process.start(
    executable,
    arguments,
    environment:
        Platform.isLinux &&
            const {'pactl', 'xdotool', 'ps', 'which'}.contains(executable)
        ? const {'LC_ALL': 'C', 'LANG': 'C'}
        : null,
  );
  final stdout = process.stdout.transform(systemEncoding.decoder).join();
  final stderr = process.stderr.transform(systemEncoding.decoder).join();
  try {
    final result = await Future.wait<Object>([
      process.exitCode,
      stdout,
      stderr,
    ]).timeout(timeout);
    return ProcessResult(process.pid, result[0] as int, result[1], result[2]);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    rethrow;
  }
}
