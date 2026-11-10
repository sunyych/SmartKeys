import 'dart:io';

import 'package:flutter/services.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import 'vibe_system_tools.dart';

abstract interface class MacSystemControl {
  Future<void> setDark(bool enabled);
}

class MethodChannelMacSystemControl implements MacSystemControl {
  const MethodChannelMacSystemControl({
    this.channel = const MethodChannel('lumiakeys/system_control'),
  });

  final MethodChannel channel;

  @override
  Future<void> setDark(bool enabled) =>
      channel.invokeMethod<void>('setDark', {'enabled': enabled});
}

abstract interface class DesktopProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
  Future<Process> start(String executable, List<String> arguments);
}

class SystemDesktopProcessRunner implements DesktopProcessRunner {
  const SystemDesktopProcessRunner();

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      Process.run(executable, arguments);

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

class DesktopActions {
  DesktopActions({
    DesktopProcessRunner? runner,
    MacSystemControl? macSystemControl,
    VibeSystemTools? vibeSystemTools,
  }) : runner = runner ?? const SystemDesktopProcessRunner(),
       macSystemControl =
           macSystemControl ?? const MethodChannelMacSystemControl(),
       vibeSystemTools = vibeSystemTools ?? VibeSystemTools();

  final DesktopProcessRunner runner;
  final MacSystemControl macSystemControl;
  final VibeSystemTools vibeSystemTools;
  int? _windowsBrightnessBeforeDark;
  Future<bool> Function()? confirmVoiceInputFirstUse;

  static final Set<String> allowedKeys = {
    'CTRL',
    'CONTROL',
    'ALT',
    'OPTION',
    'SHIFT',
    'META',
    'COMMAND',
    'WIN',
    'PRIMARY',
    'SPACE',
    'ENTER',
    'RETURN',
    'TAB',
    'ESC',
    'ESCAPE',
    'BACKSPACE',
    'DELETE',
    'HOME',
    'END',
    'PAGEUP',
    'PAGEDOWN',
    'UP',
    'DOWN',
    'LEFT',
    'RIGHT',
    '[',
    ']',
    '`',
    '/',
    '\\',
    '-',
    '=',
    ...List.generate(26, (index) => String.fromCharCode(65 + index)),
    ...List.generate(10, (index) => '$index'),
    ...List.generate(12, (index) => 'F${index + 1}'),
  };

  Future<void> executeButton(
    RemoteShortcutButton button,
    DesktopManifest manifest, {
    String? expectedAppId,
  }) async {
    if (!button.enabled) throw StateError('Shortcut is disabled');
    if (button.id.startsWith('vibe.') && button.id.endsWith('.deleteToStart')) {
      if (expectedAppId == null ||
          !button.id.startsWith('vibe.$expectedAppId.')) {
        throw StateError('Delete action requires its matching Vibe app');
      }
      await _deleteToLineStart(expectedAppId);
      return;
    }
    switch (button.targetType) {
      case RemoteTargetType.keyboardShortcut:
        await sendShortcut(button.shortcut, expectedAppId: expectedAppId);
      case RemoteTargetType.launchApplication:
        if (!manifest.settings.autoLaunchApps) {
          throw StateError('Automatic app launching is disabled');
        }
        final app = manifest.applicationById(button.target ?? '');
        await launchApplication(
          app?.executable ?? _requiredText(button.target),
        );
      case RemoteTargetType.voiceInput:
        await voiceInput();
      case RemoteTargetType.openUrl:
        await openUrl(_requiredText(button.target));
      case RemoteTargetType.macro:
      case RemoteTargetType.script:
        throw UnsupportedError(
          'Macro and Script are reserved for a future release',
        );
      case RemoteTargetType.system:
        final appId = expectedAppId;
        final actionId = button.target;
        if (appId == null || button.id != 'vibe.$appId.$actionId') {
          throw const FormatException('invalid fixed Vibe action');
        }
        await vibeSystemTools.execute(appId, _requiredText(actionId));
    }
  }

  Future<void> _deleteToLineStart(String appId) async {
    final selection = Platform.isMacOS
        ? const ['COMMAND', 'SHIFT', 'LEFT']
        : const ['SHIFT', 'HOME'];
    await sendShortcut(selection, expectedAppId: appId);
    await sendShortcut(const ['BACKSPACE'], expectedAppId: appId);
  }

  Future<void> executeLegacy(Map<String, Object?> action) async {
    switch (action['kind']) {
      case 'launch':
        await launchApplication(_requiredText(action['target']));
      case 'voiceInput':
        await voiceInput();
      case 'dark':
        await setComputerDark(
          action['enabled'] is bool ? action['enabled']! as bool : true,
        );
      case 'shortcut':
        final keys = (action['keys'] as List? ?? const [])
            .map((key) => key.toString().toUpperCase())
            .toList(growable: false);
        await sendShortcut(keys);
      default:
        throw const FormatException('unsupported action kind');
    }
  }

  Future<void> launchApplication(String target) async {
    final validated = _requiredText(target);
    if (Platform.isMacOS) {
      await _run('/usr/bin/open', ['-a', validated]);
      return;
    }
    if (Platform.isWindows) {
      final executable = _windowsExecutableAlias(validated);
      await _run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Start-Process -FilePath $args[0]',
        executable,
      ]);
      return;
    }
    await runner.start(validated, const []);
  }

  /// Activates only the three Desktop-owned Vibe application IDs. The phone
  /// supplies the ID; executable names and platform launch arguments stay here.
  Future<void> activateApplication(RemoteApplication app) async {
    final executable = switch (app.id) {
      'codex' => 'Codex',
      'claude' => 'Claude',
      'cursor' => 'Cursor',
      _ => throw const FormatException('unsupported Vibe application'),
    };
    final chatGpt =
        app.id == 'codex' && app.executable.toLowerCase().contains('chatgpt');
    final targetName = chatGpt ? 'ChatGPT' : executable;
    if (Platform.isMacOS) {
      await _run('/usr/bin/open', ['-a', targetName]);
      if (chatGpt) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await sendShortcut(const ['CTRL', '3'], expectedAppId: 'chatgpt');
      }
      return;
    }
    if (Platform.isWindows) {
      final processName = switch (app.id) {
        'codex' => chatGpt ? 'ChatGPT' : 'Codex',
        'claude' => 'Claude',
        'cursor' => 'Cursor',
        _ => throw const FormatException('unsupported Vibe application'),
      };
      final exe = '$processName.exe';
      final startAppName = chatGpt ? 'ChatGPT' : executable;
      final activationScript = r'''
& {
  param($processName, $exe, $startAppName)
  $p = Get-Process -Name $processName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) {
    $app = Get-StartApps | Where-Object { $_.Name -eq $startAppName } | Select-Object -First 1
    if ($app -and $app.AppID) { Start-Process explorer.exe -ArgumentList ("shell:AppsFolder\" + $app.AppID) }
    else { Start-Process -FilePath $exe }
    Start-Sleep -Milliseconds 900
    $p = Get-Process -Name $processName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  }
  if (-not $p) { throw "Could not launch the approved Vibe app." }
  $w = New-Object -ComObject WScript.Shell
  if (-not $w.AppActivate($p.Id)) { throw "Could not focus the approved Vibe app." }
}
''';
      final result = await runner.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        activationScript.trimRight(),
        _powershellLiteral(processName),
        _powershellLiteral(
          app.id == 'codex' ? _windowsExecutableName(chatGpt) : exe,
        ),
        _powershellLiteral(startAppName),
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'powershell.exe',
          const [],
          '${result.stderr}',
          result.exitCode,
        );
      }
      if (chatGpt) {
        await sendShortcut(const ['ALT', '3'], expectedAppId: 'chatgpt');
      }
      return;
    }
    final process = switch (app.id) {
      'codex' => 'codex',
      'claude' => 'claude',
      'cursor' => 'cursor',
      _ => throw const FormatException('unsupported Vibe application'),
    };
    final window = await runner.run('xdotool', [
      'search',
      '--onlyvisible',
      '--class',
      process,
    ]);
    if (window.exitCode == 0 && window.stdout.toString().trim().isNotEmpty) {
      await _run('xdotool', [
        'windowactivate',
        '--sync',
        window.stdout.toString().trim().split(RegExp(r'\s+')).first,
      ]);
    } else {
      await runner.start(process, const []);
    }
  }

  static String _powershellLiteral(String value) =>
      "'${value.replaceAll("'", "''")}'";

  static String _windowsExecutableName(bool chatGpt) =>
      chatGpt ? 'ChatGPT.exe' : 'Codex.exe';

  Future<void> openUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw const FormatException('Only http and https URLs are supported');
    }
    if (Platform.isMacOS) {
      await _run('/usr/bin/open', [uri.toString()]);
    } else if (Platform.isWindows) {
      await _run('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ]);
    } else {
      await _run('xdg-open', [uri.toString()]);
    }
  }

  Future<void> voiceInput() async {
    final confirm = confirmVoiceInputFirstUse;
    if (confirm != null && !await confirm()) {
      throw StateError(
        'Review the voice input explanation, then repeat the action.',
      );
    }
    await sendShortcut(const ['CTRL', 'SHIFT', 'D']);
  }

  Future<void> setComputerDark(bool enabled) async {
    if (Platform.isWindows) {
      if (enabled) {
        _windowsBrightnessBeforeDark = await _readWindowsBrightness();
      }
      final target = enabled ? 0 : (_windowsBrightnessBeforeDark ?? 70);
      await _run(
        'powershell.exe',
        const [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r'Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods '
                  r'| ForEach-Object { Invoke-CimMethod -InputObject $_ '
                  r'-MethodName WmiSetBrightness '
                  r'-Arguments @{Timeout=1;Brightness=$args[0]} | Out-Null }',
            ] +
            ['$target'],
      );
      if (!enabled) _windowsBrightnessBeforeDark = null;
      return;
    }
    if (Platform.isMacOS) {
      await macSystemControl.setDark(enabled);
      return;
    }
    await _run('brightnessctl', ['set', enabled ? '1%' : '100%']);
  }

  Future<int?> _readWindowsBrightness() async {
    final result = await runner.run('powershell.exe', const [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness '
          r'| Select-Object -First 1 -ExpandProperty CurrentBrightness)',
    ]);
    if (result.exitCode != 0) return null;
    return int.tryParse('${result.stdout}'.trim());
  }

  Future<void> sendShortcut(
    List<String> rawKeys, {
    String? expectedAppId,
  }) async {
    var keys = rawKeys
        .map((key) => key.trim().toUpperCase())
        .map(
          (key) => key == 'PRIMARY'
              ? Platform.isMacOS
                    ? 'COMMAND'
                    : 'CTRL'
              : key,
        )
        .toList(growable: false);
    keys = switch (keys) {
      ['BROWSER_BACK'] =>
        Platform.isMacOS ? const ['COMMAND', '['] : const ['ALT', 'LEFT'],
      ['BROWSER_FORWARD'] =>
        Platform.isMacOS ? const ['COMMAND', ']'] : const ['ALT', 'RIGHT'],
      _ => keys,
    };
    if (keys.isEmpty || keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException('unsupported shortcut');
    }
    if (Platform.isWindows) {
      await _sendWindowsShortcut(keys, expectedAppId: expectedAppId);
    } else if (Platform.isMacOS) {
      await _sendMacShortcut(keys, expectedAppId: expectedAppId);
    } else {
      if (expectedAppId != null && !await _foregroundMatches(expectedAppId)) {
        throw StateError(
          'Switch to the matching Vibe app before using this shortcut',
        );
      }
      await _run('xdotool', ['key', keys.join('+')]);
    }
  }

  Future<void> _sendWindowsShortcut(
    List<String> keys, {
    String? expectedAppId,
  }) async {
    final modifiers = StringBuffer();
    final normal = <String>[];
    for (final key in keys) {
      switch (key) {
        case 'CTRL':
        case 'CONTROL':
          modifiers.write('^');
        case 'ALT':
        case 'OPTION':
          modifiers.write('%');
        case 'SHIFT':
          modifiers.write('+');
        case 'META':
        case 'COMMAND':
        case 'WIN':
          throw const FormatException(
            'Windows-key shortcuts are not supported yet',
          );
        default:
          normal.add(_windowsSendKey(key));
      }
    }
    if (normal.length != 1) {
      throw const FormatException('shortcut needs one non-modifier key');
    }
    final targetNames = _foregroundProcessNames(expectedAppId);
    final script = r'''
& {
param($approvedProcesses, $keyStroke)
if ($approvedProcesses) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LK { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId); }
'@
$targetProcessId = 0
[LK]::GetWindowThreadProcessId([LK]::GetForegroundWindow(), [ref]$targetProcessId) | Out-Null
$p = if ($targetProcessId -ne 0) { Get-Process -Id $targetProcessId -ErrorAction SilentlyContinue }
if (-not $p -or @($approvedProcesses -split ",") -notcontains $p.ProcessName.ToLowerInvariant()) { throw "Switch to the matching Vibe app before using this shortcut." }
}
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait($keyStroke)
}
''';
    await _run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script.trimRight(),
      _powershellLiteral(targetNames?.join(',') ?? ''),
      _powershellLiteral('$modifiers${normal.single}'),
    ]);
  }

  Future<void> _sendMacShortcut(
    List<String> keys, {
    String? expectedAppId,
  }) async {
    final modifiers = <String>[];
    final normal = <String>[];
    for (final key in keys) {
      if (key == 'CTRL' || key == 'CONTROL') {
        modifiers.add('control down');
      } else if (key == 'ALT' || key == 'OPTION') {
        modifiers.add('option down');
      } else if (key == 'SHIFT') {
        modifiers.add('shift down');
      } else if (key == 'META' || key == 'COMMAND' || key == 'WIN') {
        modifiers.add('command down');
      } else {
        normal.add(key);
      }
    }
    if (normal.length != 1) {
      throw const FormatException('shortcut needs one non-modifier key');
    }
    final suffix = modifiers.isEmpty ? '' : ' using {${modifiers.join(', ')}}';
    final keyCode = _macKeyCode(normal.single);
    final instruction = keyCode == null
        ? 'keystroke "${_escapeAppleScript(normal.single.toLowerCase())}"$suffix'
        : 'key code $keyCode$suffix';
    final guard = switch (expectedAppId) {
      'codex' =>
        'set frontName to name of first application process whose frontmost is true\nif frontName is not "Codex" and frontName is not "ChatGPT" then error "Switch to Codex before using this shortcut."\n',
      'chatgpt' =>
        'set frontName to name of first application process whose frontmost is true\nif frontName is not "ChatGPT" then error "Switch to ChatGPT before using this shortcut."\n',
      'claude' =>
        'set frontName to name of first application process whose frontmost is true\nif frontName is not "Claude" and frontName is not "Claude Code" then error "Switch to Claude before using this shortcut."\n',
      'cursor' =>
        'set frontName to name of first application process whose frontmost is true\nif frontName is not "Cursor" then error "Switch to Cursor before using this shortcut."\n',
      _ => '',
    };
    await _run('/usr/bin/osascript', [
      '-e',
      'tell application "System Events"\n$guard$instruction\nend tell',
    ]);
  }

  static List<String>? _foregroundProcessNames(String? appId) =>
      switch (appId) {
        'codex' => ['codex', 'chatgpt'],
        'chatgpt' => ['chatgpt'],
        'claude' => ['claude'],
        'cursor' => ['cursor'],
        _ => null,
      };

  Future<bool> _foregroundMatches(String appId) async {
    final processNames = _foregroundProcessNames(appId);
    if (processNames == null) return false;
    if (Platform.isWindows) {
      return false; // Windows is checked atomically in SendKeys.
    }
    if (Platform.isMacOS) {
      final result = await runner.run('/usr/bin/osascript', const [
        '-e',
        'tell application "System Events" to get name of first application process whose frontmost is true',
      ]);
      if (result.exitCode != 0) return false;
      final name = result.stdout.toString().toLowerCase();
      return switch (appId) {
        'codex' => name == 'codex' || name == 'chatgpt',
        'chatgpt' => name == 'chatgpt',
        'claude' => name == 'claude' || name == 'claude code',
        'cursor' => name == 'cursor',
        _ => false,
      };
    }
    final active = await runner.run('xdotool', const [
      'getactivewindow',
      'getwindowpid',
    ]);
    final pid = int.tryParse(active.stdout.toString().trim());
    if (active.exitCode != 0 || pid == null) return false;
    final process = await runner.run('ps', ['-p', '$pid', '-o', 'comm=']);
    final name = process.stdout.toString().trim().toLowerCase();
    return process.exitCode == 0 && processNames.any(name.contains);
  }

  static String _windowsSendKey(String key) => switch (key) {
    'ENTER' || 'RETURN' => '{ENTER}',
    'TAB' => '{TAB}',
    'ESC' || 'ESCAPE' => '{ESC}',
    'SPACE' => ' ',
    'BACKSPACE' => '{BACKSPACE}',
    'DELETE' => '{DELETE}',
    'UP' => '{UP}',
    'DOWN' => '{DOWN}',
    'LEFT' => '{LEFT}',
    'RIGHT' => '{RIGHT}',
    'HOME' => '{HOME}',
    'END' => '{END}',
    'PAGEUP' => '{PGUP}',
    'PAGEDOWN' => '{PGDN}',
    _ when RegExp(r'^F([1-9]|1[0-2])$').hasMatch(key) => '{$key}',
    _ => key.toLowerCase(),
  };

  static int? _macKeyCode(String key) => switch (key) {
    'ENTER' || 'RETURN' => 36,
    'TAB' => 48,
    'SPACE' => 49,
    'BACKSPACE' => 51,
    'ESC' || 'ESCAPE' => 53,
    'DELETE' => 117,
    'HOME' => 115,
    'END' => 119,
    'PAGEUP' => 116,
    'PAGEDOWN' => 121,
    'LEFT' => 123,
    'RIGHT' => 124,
    'DOWN' => 125,
    'UP' => 126,
    'F1' => 122,
    'F2' => 120,
    'F3' => 99,
    'F4' => 118,
    'F5' => 96,
    'F6' => 97,
    'F7' => 98,
    'F8' => 100,
    'F9' => 101,
    'F10' => 109,
    'F11' => 103,
    'F12' => 111,
    _ => null,
  };

  static String _windowsExecutableAlias(String target) =>
      switch (target.toLowerCase()) {
        'visual studio code' || 'vscode' => 'Code.exe',
        'google chrome' || 'chrome' => 'chrome.exe',
        'adobe photoshop' || 'photoshop' => 'Photoshop.exe',
        'adobe illustrator' || 'illustrator' => 'Illustrator.exe',
        'adobe premiere pro' || 'premiere' => 'Adobe Premiere Pro.exe',
        'codex' => 'Codex.exe',
        _ => target,
      };

  static String _requiredText(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 500 || text.contains('\u0000')) {
      throw const FormatException('invalid desktop target');
    }
    return text;
  }

  static String _escapeAppleScript(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  Future<void> _run(String executable, List<String> arguments) async {
    final result = await runner.run(executable, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }
}
