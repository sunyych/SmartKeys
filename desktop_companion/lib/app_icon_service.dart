import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

/// Reads an installed app's local icon. This never resolves a URL or accepts
/// arbitrary executable names from remote actions; `application.executable`
/// comes from the desktop-owned manifest.
class NativeAppIconService {
  NativeAppIconService({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('lumiakeys/app_icon');

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

  Future<Uint8List?> getNativeIcon(RemoteApplication application) async {
    if (!supportedAppIds.contains(application.id)) return null;
    if (Platform.isLinux) return _linuxDesktopIcon(application);
    if (Platform.isWindows) return _windowsNativeIcon(application.id);
    if (!Platform.isMacOS) return null;
    try {
      final bytes = await channel.invokeMethod<Uint8List>('get', {
        'appId': application.id,
        'executable': application.executable,
      });
      if (bytes == null || bytes.isEmpty || bytes.length > 64 * 1024)
        return null;
      return bytes;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<Uint8List?> _windowsNativeIcon(String appId) async {
    const script = r'''
$executables = switch ($args[0]) {
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
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
        appId,
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;
      final encoded = '${result.stdout}'.trim();
      if (encoded.isEmpty || encoded.length > 88 * 1024) return null;
      final bytes = base64Decode(encoded);
      return bytes.length <= 64 * 1024 && _isPng(bytes) ? bytes : null;
    } on ProcessException {
      return null;
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<Uint8List?> _linuxDesktopIcon(RemoteApplication application) async {
    final aliases = _linuxAliases(application.id, application.executable);
    final roots = <String>[
      if (Platform.environment['HOME'] case final home?)
        '$home/.local/share/applications',
      '/usr/local/share/applications',
      '/usr/share/applications',
    ];
    final iconNames = <String>[];
    for (final root in roots) {
      final directory = Directory(root);
      if (!await directory.exists()) continue;
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File || !entry.path.endsWith('.desktop')) continue;
        final contents = await entry.readAsString().catchError((_) => '');
        final desktop = _desktopEntry(contents);
        if (desktop == null) continue;
        final name = (desktop['Name'] ?? '').toLowerCase();
        final exec = (desktop['Exec'] ?? '').toLowerCase();
        final file = entry.uri.pathSegments.last.toLowerCase();
        if (!aliases.any(
          (alias) =>
              name.contains(alias) ||
              exec.contains(alias) ||
              file.contains(alias),
        ))
          continue;
        final icon = desktop['Icon'];
        if (icon != null && icon.isNotEmpty) iconNames.add(icon);
      }
    }
    for (final name in iconNames) {
      final candidates = _linuxIconCandidates(name);
      for (final path in candidates) {
        final file = File(path);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        if (bytes.length <= 64 * 1024 && _isPng(bytes)) return bytes;
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
        if (split > 0)
          values[line.substring(0, split)] = line.substring(split + 1);
      }
    }
    return inEntry ? values : null;
  }

  static List<String> _linuxAliases(String id, String executable) {
    final alias = switch (id) {
      'codex' || 'chatgpt' => const ['codex', 'chatgpt', 'openai'],
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

  static List<String> _linuxIconCandidates(String icon) {
    if (icon.startsWith('/'))
      return [if (icon.toLowerCase().endsWith('.png')) icon];
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
    final roots = <String>[
      if (Platform.environment['HOME'] case final home?)
        '$home/.local/share/icons',
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

  static bool _isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;
}
