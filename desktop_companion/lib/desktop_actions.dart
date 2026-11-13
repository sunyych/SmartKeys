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
        r'& { Start-Process -FilePath $args[0] }',
        _powershellLiteral(executable),
      ]);
      return;
    }
    await runner.start(validated, const []);
  }

  /// Activates only Desktop-owned application IDs. Executables and native
  /// launch arguments are resolved here rather than supplied by the phone.
  Future<void> activateApplication(RemoteApplication app) async {
    final executable = switch (app.id) {
      'codex' => 'Codex',
      'chatgpt' => 'ChatGPT',
      'claude' => 'Claude',
      'cursor' => 'Cursor',
      'chrome' => 'Google Chrome',
      'edge' => 'Microsoft Edge',
      'firefox' => 'Firefox',
      'safari' => 'Safari',
      'teams' => 'Microsoft Teams',
      'zoom' => 'zoom.us',
      _ => throw const FormatException('unsupported managed application'),
    };
    final chatGpt =
        app.id == 'chatgpt' ||
        (app.id == 'codex' &&
            app.executable.toLowerCase().contains('chatgpt'));
    final chatViewKey = app.id == 'chatgpt' ? '1' : '3';
    final targetName = chatGpt ? 'ChatGPT' : executable;
    if (Platform.isMacOS) {
      await _run('/usr/bin/open', ['-a', targetName]);
      if (chatGpt && await _waitForForeground('chatgpt')) {
        await sendShortcut(['CTRL', chatViewKey], expectedAppId: 'chatgpt');
      }
      return;
    }
    if (Platform.isWindows) {
      if (app.id == 'safari') {
        throw const FormatException('Safari is only available on Mac');
      }
      final processNames = switch (app.id) {
        'chatgpt' => const ['ChatGPT'],
        'codex' => chatGpt ? const ['ChatGPT'] : const ['Codex'],
        'claude' => const ['Claude'],
        'cursor' => const ['Cursor'],
        'chrome' => const ['chrome'],
        'edge' => const ['msedge'],
        'firefox' => const ['firefox'],
        'safari' => throw const FormatException(
          'Safari is only available on Mac',
        ),
        'teams' => const ['ms-teams', 'teams'],
        'zoom' => const ['Zoom', 'cpt-host'],
        _ => throw const FormatException('unsupported managed application'),
      };
      final processNameArgument = processNames.join(',');
      final executableNames = switch (app.id) {
        'chatgpt' => const ['ChatGPT.exe'],
        'codex' => chatGpt ? const ['ChatGPT.exe'] : const ['Codex.exe'],
        'claude' => const ['Claude.exe'],
        'cursor' => const ['Cursor.exe'],
        'chrome' => const ['chrome.exe'],
        'edge' => const ['msedge.exe'],
        'firefox' => const ['firefox.exe'],
        'teams' => const ['ms-teams.exe', 'Teams.exe'],
        'zoom' => const ['Zoom.exe'],
        _ => throw const FormatException('unsupported managed application'),
      };
      final executableNameArgument = executableNames.join(',');
      final startAppName = switch (app.id) {
        'chatgpt' => 'ChatGPT',
        'codex' => chatGpt ? 'ChatGPT' : 'Codex',
        'claude' => 'Claude',
        'cursor' => 'Cursor',
        'chrome' => 'Google Chrome',
        'edge' => 'Microsoft Edge',
        'firefox' => 'Firefox,Mozilla Firefox',
        'teams' => 'Teams,Microsoft Teams,Microsoft Teams classic',
        'zoom' => 'Zoom,Zoom Workplace,Zoom Meetings',
        _ => throw const FormatException('unsupported managed application'),
      };
      final activationScript = r'''
& {
  $processNames = $args[0] -split ','
  $executables = $args[1] -split ','
  $startAppNames = $args[2] -split ','
  $running = @(Get-Process -Name $processNames -ErrorAction SilentlyContinue)
  $p = $running | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) {
    $app = Get-StartApps | Where-Object { $startAppNames -contains $_.Name } | Select-Object -First 1
    if ($app -and $app.AppID) {
      Start-Process explorer.exe -ArgumentList ("shell:AppsFolder\" + $app.AppID)
    } elseif (-not $running) {
      $uninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
      )
      $installLocations = @()
      foreach ($installedApp in (Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue)) {
        $displayName = [string]$installedApp.DisplayName
        foreach ($alias in $startAppNames) {
          if ($displayName -like ("*" + $alias + "*") -and $installedApp.InstallLocation) {
            $installLocations += [string]$installedApp.InstallLocation
            break
          }
        }
      }
      $executablePath = $null
      foreach ($exe in $executables) {
        $appPathKeys = @(
          "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$exe",
          "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\$exe",
          "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$exe"
        )
        foreach ($key in $appPathKeys) {
          if (Test-Path $key) {
            $registeredPath = (Get-Item $key).GetValue('')
            if ($registeredPath -and (Test-Path $registeredPath)) {
              $executablePath = $registeredPath
              break
            }
          }
        }
        if (-not $executablePath) {
          foreach ($location in $installLocations) {
            $candidatePath = Join-Path $location $exe
            if (Test-Path $candidatePath) { $executablePath = $candidatePath; break }
          }
        }
        if (-not $executablePath) {
          $command = Get-Command $exe -ErrorAction SilentlyContinue
          if ($command) { $executablePath = $command.Source }
        }
        if ($executablePath) { break }
      }
      if ($executablePath) { Start-Process -FilePath $executablePath }
      else { throw "The selected app is installed but its launch entry is unavailable." }
    }
  }
  if (-not $p) {
    $focusDeadline = [DateTime]::UtcNow.AddMilliseconds(2750)
    do {
      $p = Get-Process -Name $processNames -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
      if ($p) { break }
      Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $focusDeadline)
  }
  if (-not $p) {
    if ($startAppNames -contains 'ChatGPT') {
      throw 'ChatGPT did not expose a main window; refusing to report activation success.'
    }
    Write-Output 'STARTING'
    return
  }
  $w = New-Object -ComObject WScript.Shell
  # AppActivate can report success without changing the foreground window.
  # ChatGPT view shortcuts are only safe after verifying its actual HWND.
  if ($startAppNames -contains 'ChatGPT') {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LumiaWindowActivation {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
'@
    $hwnd = [IntPtr]$p.MainWindowHandle
    if (-not [LumiaWindowActivation]::IsWindowVisible($hwnd)) {
      throw 'ChatGPT main window is not visible; refusing to send view shortcuts.'
    }
    if ([LumiaWindowActivation]::IsIconic($hwnd)) {
      [void][LumiaWindowActivation]::ShowWindowAsync($hwnd, 9)
      Start-Sleep -Milliseconds 100
    }
    [void]$w.AppActivate($p.Id)
    Start-Sleep -Milliseconds 100
    if ([LumiaWindowActivation]::GetForegroundWindow() -ne $hwnd) {
      # Do not synthesize Alt if the user is physically holding it.
      if (([LumiaWindowActivation]::GetAsyncKeyState(0x12) -band 0x8000) -ne 0) {
        throw 'ChatGPT could not be focused while Alt is held; no view shortcut was sent.'
      }
      [LumiaWindowActivation]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
      try {
        [void][LumiaWindowActivation]::SetForegroundWindow($hwnd)
        Start-Sleep -Milliseconds 100
      } finally {
        [LumiaWindowActivation]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
      }
    }
    if ([LumiaWindowActivation]::GetForegroundWindow() -ne $hwnd) {
      throw 'Windows did not activate the ChatGPT main window; no view shortcut was sent.'
    }
    Write-Output 'FOCUSED'
    return
  }
  if ($w.AppActivate($p.Id)) { Write-Output 'FOCUSED' }
  else { Write-Output 'STARTING' }
}
''';
      final result = await runner.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        activationScript.trimRight(),
        _powershellLiteral(processNameArgument),
        _powershellLiteral(executableNameArgument),
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
      if (chatGpt && result.stdout.toString().contains('FOCUSED')) {
        await sendShortcut(['ALT', chatViewKey], expectedAppId: 'chatgpt');
      }
      return;
    }
    final process = switch (app.id) {
      'chatgpt' => 'chatgpt',
      'codex' => 'codex',
      'claude' => 'claude',
      'cursor' => 'cursor',
      'chrome' => 'google-chrome',
      'edge' => 'microsoft-edge',
      'firefox' => 'firefox',
      'safari' => throw const FormatException(
        'Safari is only available on Mac',
      ),
      'teams' => 'teams-for-linux',
      'zoom' => 'zoom',
      _ => throw const FormatException('unsupported managed application'),
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
      var executable = process;
      if (app.id == 'edge') {
        for (final candidate in const [
          'microsoft-edge',
          'microsoft-edge-stable',
        ]) {
          final result = await runner.run('which', [candidate]);
          final path = result.stdout.toString().trim();
          if (result.exitCode == 0 && path.isNotEmpty) {
            executable = path;
            break;
          }
        }
      }
      await runner.start(executable, const []);
    }
    if (app.id == 'chatgpt' && await _waitForForeground('chatgpt')) {
      await sendShortcut(const ['ALT', '1'], expectedAppId: 'chatgpt');
    }
  }

  static String _powershellLiteral(String value) =>
      "'${value.replaceAll("'", "''")}'";

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
      'chrome' || 'edge' || 'firefox' || 'safari' =>
        'set frontName to name of first application process whose frontmost is true\nif frontName is not "${_macApplicationName(expectedAppId!)}" then error "Switch to the selected app before using this shortcut."\n',
      'teams' =>
        'set frontName to name of first application process whose frontmost is true\nif frontName is not "Microsoft Teams" and frontName is not "Microsoft Teams classic" then error "Switch to the selected app before using this shortcut."\n',
      'zoom' =>
        'set frontName to name of first application process whose frontmost is true\nif frontName is not "zoom.us" and frontName is not "Zoom Workplace" then error "Switch to the selected app before using this shortcut."\n',
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
        'chrome' => ['chrome', 'google chrome'],
        'edge' => ['microsoft edge', 'msedge', 'microsoft-edge-stable'],
        'firefox' => ['firefox'],
        'safari' => ['safari'],
        'teams' => ['ms-teams', 'teams'],
        'zoom' => ['zoom', 'cpt-host'],
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
        'chrome' => name == 'google chrome' || name == 'chrome',
        'edge' => name == 'microsoft edge',
        'firefox' => name == 'firefox',
        'safari' => name == 'safari',
        'teams' =>
          name == 'microsoft teams' || name == 'microsoft teams classic',
        'zoom' => name == 'zoom.us' || name == 'zoom workplace',
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

  Future<bool> _waitForForeground(String appId) async {
    for (var attempt = 0; attempt < 16; attempt++) {
      if (await _foregroundMatches(appId)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
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

  static String _macApplicationName(String id) => switch (id) {
    'chrome' => 'Google Chrome',
    'edge' => 'Microsoft Edge',
    'firefox' => 'Firefox',
    'safari' => 'Safari',
    _ => throw const FormatException('unsupported Mac application'),
  };

  static String _windowsExecutableAlias(String target) =>
      switch (target.toLowerCase()) {
        'visual studio code' || 'vscode' => 'Code.exe',
        'google chrome' || 'chrome' => 'chrome.exe',
        'microsoft edge' || 'edge' => 'msedge.exe',
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
