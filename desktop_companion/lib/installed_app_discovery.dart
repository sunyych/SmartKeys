import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;

import 'icons/builtin_icon_catalog.g.dart';
import 'installed_app_registry.dart';

typedef InstalledProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// OS inventory is scanned only by the registry's cached/manual refresh path.
/// It is deliberately independent from the three-second foreground monitor.
class PlatformInstalledApplicationDiscovery {
  PlatformInstalledApplicationDiscovery({
    TargetPlatform? platform,
    this.runner,
    MethodChannel? channel,
    this.macRoots,
    this.timeout = const Duration(seconds: 15),
  }) : platform = platform ?? defaultTargetPlatform,
       channel = channel ?? const MethodChannel('lumiakeys/installed_apps');
  final TargetPlatform platform;
  final InstalledProcessRunner? runner;
  final MethodChannel channel;
  final List<String>? macRoots;
  final Duration timeout;

  Future<List<InstalledLaunchTarget>> discover() async => switch (platform) {
    TargetPlatform.windows => _windows(),
    TargetPlatform.macOS => _mac(),
    TargetPlatform.linux => _linux(),
    _ => const [],
  };

  Future<ProcessResult> _run(String executable, List<String> arguments) async {
    final injected = runner;
    if (injected != null) {
      return injected(executable, arguments).timeout(timeout);
    }
    final process = await Process.start(executable, arguments);
    Future<String> bounded(Stream<List<int>> stream) async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          process.kill();
          throw const FormatException(
            'Installed application inventory exceeds its bound',
          );
        }
        bytes.add(chunk);
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: false);
    }

    try {
      final values = await Future.wait<Object>([
        process.exitCode,
        bounded(process.stdout),
        bounded(process.stderr),
      ]).timeout(timeout);
      return ProcessResult(process.pid, values[0] as int, values[1], values[2]);
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }

  Future<List<InstalledLaunchTarget>> _windows() async {
    final result = await _run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      windowsInventoryScript,
    ]);
    if (result.exitCode != 0) {
      throw const FileSystemException(
        'Windows application inventory is unavailable',
      );
    }
    return parseInventory(result.stdout.toString(), TargetPlatform.windows);
  }

  Future<List<InstalledLaunchTarget>> _linux() async {
    // GIO owns XDG precedence, visibility, DBus and Exec field-code semantics.
    // No command-line string is parsed or executed by the Dart scanner.
    final rows = await channel
        .invokeMethod<Object?>('discover')
        .timeout(timeout);
    return parseInventory(jsonEncode(rows), TargetPlatform.linux);
  }

  Future<List<InstalledLaunchTarget>> _mac() async {
    final bundles = <String>{};
    Future<void> visit(Directory root, int depth) async {
      if (depth > 6 || !await root.exists()) return;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (entity.path.endsWith('.app')) {
          bundles.add(entity.path);
        } else if (!paths.basename(entity.path).startsWith('.')) {
          await visit(entity, depth + 1);
        }
        if (bundles.length > 2000) {
          throw const FormatException('Too many application bundles');
        }
      }
    }

    for (final root
        in macRoots ??
            [
              '/Applications',
              '/System/Applications',
              paths.join(Platform.environment['HOME'] ?? '/', 'Applications'),
            ]) {
      await visit(Directory(root), 0);
    }
    try {
      final indexed = await _run('/usr/bin/mdfind', [
        "kMDItemContentTypeTree == 'com.apple.application-bundle'",
      ]);
      if (indexed.exitCode == 0) {
        for (final entry in indexed.stdout.toString().split('\n')) {
          final path = entry.trim();
          if (paths.posix.isAbsolute(path) &&
              path.endsWith('.app') &&
              !path.contains('.app/')) {
            bundles.add(path);
          }
          if (bundles.length > 2000) {
            throw const FormatException('Too many application bundles');
          }
        }
      }
    } on ProcessException {
      /* Standard-directory fallback works without an index. */
    }
    if (bundles.isEmpty) return [];
    final result = await _run('/usr/bin/osascript', [
      '-l',
      'JavaScript',
      '-e',
      macInventoryScript,
      jsonEncode(bundles.toList()),
    ]);
    if (result.exitCode != 0) {
      throw const FileSystemException(
        'macOS application inventory is unavailable',
      );
    }
    return parseInventory(result.stdout.toString(), TargetPlatform.macOS);
  }

  static List<InstalledLaunchTarget> parseInventory(
    String raw,
    TargetPlatform platform,
  ) {
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('Application inventory exceeds its bound');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.length > 2000) {
      throw const FormatException('Invalid application inventory');
    }
    final entries = <String, InstalledLaunchTarget>{};
    for (final value in decoded) {
      if (value is! Map) {
        throw const FormatException('Invalid installed application');
      }
      String required(String key) {
        final field = value[key];
        if (field is! String || field.isEmpty) {
          throw const FormatException('Invalid installed application field');
        }
        return field;
      }

      String? optional(String key) =>
          value[key] is String && (value[key] as String).isNotEmpty
          ? value[key] as String
          : null;
      final name = required('name'),
          identity = required('identity'),
          locator = required('locator');
      final kind = switch (platform) {
        TargetPlatform.windows => switch (value['kind']) {
          'windowsAppId' => InstalledLaunchKind.windowsAppId,
          'windowsShortcut' => InstalledLaunchKind.windowsShortcut,
          'windowsExecutable' => InstalledLaunchKind.windowsExecutable,
          _ => throw const FormatException('Invalid Windows application kind'),
        },
        TargetPlatform.macOS => InstalledLaunchKind.macBundle,
        TargetPlatform.linux => InstalledLaunchKind.linuxDesktopEntry,
        _ => throw const FormatException(
          'Unsupported installed application platform',
        ),
      };
      final target = InstalledLaunchTarget.discovered(
        name: name,
        kind: kind,
        identity: identity,
        locator: locator,
        executablePath: optional('executablePath'),
        startupWMClass: optional('startupWMClass'),
        iconKey: iconForName(name) ?? optional('iconKey'),
      );
      validateInstalledTarget(target);
      final previous = entries[target.id];
      if (previous != null && previous.locator != target.locator) {
        throw const FormatException(
          'Conflicting installed application identity',
        );
      }
      entries[target.id] = target;
    }
    return entries.values.toList();
  }

  static String? iconForName(String name) {
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final value = normalize(name);
    for (final icon in builtinIconCatalog) {
      if ([
        icon.id,
        icon.name,
        ...icon.aliases,
      ].any((text) => normalize(text) == value)) {
        return icon.id;
      }
    }
    return null;
  }

  /// Fixed, local OS enumeration only. No remote target is interpolated.
  static const windowsInventoryScript = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$items = New-Object System.Collections.Generic.List[object]
$identities = @{}
function Add-Installed($name, $kind, $identity, $locator, $executable) {
  if (-not $name -or -not $identity -or -not $locator) { return }
  $key = $kind + '|' + $identity
  if ($identities.ContainsKey($key)) { return }
  $identities[$key] = $true
  $items.Add([pscustomobject]@{name=[string]$name;kind=$kind;identity=[string]$identity;locator=[string]$locator;executablePath=$executable})
  if ($items.Count -gt 2000) { throw 'Application inventory exceeds its bound' }
}
Get-StartApps | ForEach-Object { Add-Installed $_.Name 'windowsAppId' ('aumid:' + $_.AppID) $_.AppID $null }
$shell = New-Object -ComObject WScript.Shell
$roots = @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))
for ($scope=0; $scope -lt $roots.Count; $scope++) {
  $root = $roots[$scope]
  if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
  Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -Depth 6 -ErrorAction Stop | ForEach-Object {
    $link = $shell.CreateShortcut($_.FullName)
    $target = [Environment]::ExpandEnvironmentVariables([string]$link.TargetPath)
    if ($target -and (Test-Path -LiteralPath $target -PathType Leaf) -and ([IO.Path]::GetExtension($target) -in @('.exe','.com'))) {
      $relative = $_.FullName.Substring($root.Length).ToLowerInvariant()
      Add-Installed $_.BaseName 'windowsShortcut' ('startmenu:' + $scope + ':' + $relative) $_.FullName $target
    }
  }
}
$appPaths = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')
foreach ($root in $appPaths) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  Get-ChildItem -LiteralPath $root -ErrorAction Stop | ForEach-Object {
    $target = [string]$_.GetValue('')
    if ($target) { $target = [Environment]::ExpandEnvironmentVariables($target.Trim('"')) }
    if ($target -and [IO.Path]::IsPathRooted($target) -and (Test-Path -LiteralPath $target -PathType Leaf) -and $target.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)) {
      Add-Installed $_.PSChildName 'windowsExecutable' ('apppath:' + $target.ToLowerInvariant()) $target $target
    }
  }
}
ConvertTo-Json -InputObject @($items.ToArray()) -Compress -Depth 4
''';

  static const macInventoryScript = r'''
ObjC.import('Foundation'); ObjC.import('AppKit');
function run(argv) {
  const paths = JSON.parse(argv[0]); const byIdentity = {};
  for (const path of paths) {
    try {
    const url = $.NSURL.fileURLWithPath(path); let bundle = $.NSBundle.bundleWithURL(url);
    if (!bundle || !bundle.bundleIdentifier || !bundle.executableURL) continue;
    const id = ObjC.unwrap(bundle.bundleIdentifier);
    const preferred = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(id);
    const chosen = preferred ? ObjC.unwrap(preferred.path) : path;
    bundle = $.NSBundle.bundleWithURL($.NSURL.fileURLWithPath(chosen));
    if (!bundle || !bundle.executableURL) continue;
    const info = bundle.infoDictionary;
    const label = info.objectForKey('CFBundleDisplayName') || info.objectForKey('CFBundleName');
    const name = label ? ObjC.unwrap(label) : chosen.split('/').pop().replace(/\.app$/, '');
    if (typeof name !== 'string' || !name || typeof id !== 'string' || !id) continue;
    byIdentity[id] = {name:name,identity:'bundle:'+id,locator:chosen,executablePath:ObjC.unwrap(bundle.executableURL.path)};
    } catch (_) { continue; }
  }
  return JSON.stringify(Object.values(byIdentity));
}
''';
}
