import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'installed_app_registry.dart';

typedef InstalledTargetResolver = InstalledLaunchTarget? Function(String id);

/// Local OS handoff only. No executable, argument or URL comes from an RPC.
class InstalledApplicationLauncher {
  InstalledApplicationLauncher({
    required this.resolve,
    MethodChannel? channel,
    this.platformOverride,
    Future<bool> Function(InstalledLaunchTarget)? targetExists,
    this.timeout = const Duration(seconds: 8),
  }) : channel = channel ?? const MethodChannel('lumiakeys/installed_apps'),
       targetExists = targetExists ?? installedTargetExists;
  final InstalledTargetResolver resolve;
  final MethodChannel channel;
  final TargetPlatform? platformOverride;
  final Future<bool> Function(InstalledLaunchTarget) targetExists;
  final Duration timeout;
  TargetPlatform get platform =>
      platformOverride ??
      (Platform.isWindows
          ? TargetPlatform.windows
          : Platform.isMacOS
          ? TargetPlatform.macOS
          : TargetPlatform.linux);
  bool _matchesPlatform(InstalledLaunchKind kind) => switch (platform) {
    TargetPlatform.windows => {
      InstalledLaunchKind.windowsAppId,
      InstalledLaunchKind.windowsShortcut,
      InstalledLaunchKind.windowsExecutable,
    }.contains(kind),
    TargetPlatform.macOS => kind == InstalledLaunchKind.macBundle,
    TargetPlatform.linux => {
      InstalledLaunchKind.linuxDesktopEntry,
      InstalledLaunchKind.linuxExecutable,
    }.contains(kind),
    _ => false,
  };
  InstalledLaunchTarget? registeredTarget(String id) {
    if (!isInstalledApplicationId(id)) return null;
    try {
      final target = resolve(id);
      if (target == null ||
          target.id != id ||
          !target.available ||
          !_matchesPlatform(target.kind)) {
        return null;
      }
      validateInstalledTarget(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  bool _stillRegistered(InstalledLaunchTarget target) {
    final current = registeredTarget(target.id);
    return current != null &&
        current.kind == target.kind &&
        current.identity == target.identity &&
        current.locator == target.locator;
  }

  Future<InstalledLaunchTarget> _prepare(String id) async {
    try {
      final target = registeredTarget(id);
      if (target != null &&
          await targetExists(target).timeout(timeout) &&
          _stillRegistered(target)) {
        return target;
      }
    } catch (_) {
      // Filesystem/registry failures may contain private locators; do not echo.
    }
    throw StateError(
      'The registered application is unavailable. Refresh installed applications on the computer.',
    );
  }

  Future<void> launch(String id, {bool Function(String id)? authorize}) async {
    final target = await _prepare(id);
    try {
      // No await between the final mutable-configuration check and dispatch.
      if (authorize != null && !authorize(id)) {
        throw StateError(
          'The registered application launch is no longer authorized.',
        );
      }
      final accepted = await channel
          .invokeMethod<bool>('launch', {
            'kind': target.kind.name,
            'locator': target.locator,
          })
          .timeout(timeout);
      if (accepted != true) {
        throw StateError(
          'The operating system did not accept this application launch.',
        );
      }
    } on TimeoutException {
      throw TimeoutException('Registered application launch timed out.');
    } catch (_) {
      throw StateError(
        'The operating system could not launch the registered application.',
      );
    }
  }

  Future<Uint8List?> icon(String id) async {
    final target = await _prepare(id);
    final bytes = await channel
        .invokeMethod<Uint8List>('icon', {
          'kind': target.kind.name,
          'locator': target.locator,
        })
        .timeout(timeout);
    return _stillRegistered(target) ? bytes : null;
  }
}
