import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/installed_app_launcher.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/app_icon_service.dart';

InstalledLaunchTarget target(InstalledLaunchKind kind, String locator) =>
    InstalledLaunchTarget.discovered(
      name: "Example O'Brien App",
      kind: kind,
      identity: 'os-identity:$locator',
      locator: locator,
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/installed-apps');
  final calls = <MethodCall>[];
  setUp(() => calls.clear());
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  void handle(Future<Object?> Function(MethodCall)? callback) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return callback == null ? true : await callback(call);
        });
  }

  test(
    'each registered target uses native kind/location only, without shell arguments',
    () async {
      final cases = [
        (
          InstalledLaunchKind.windowsAppId,
          'Example.Company!Main',
          TargetPlatform.windows,
        ),
        (
          InstalledLaunchKind.windowsShortcut,
          r"C:\Apps\O'Brien\Example.lnk",
          TargetPlatform.windows,
        ),
        (
          InstalledLaunchKind.windowsExecutable,
          r'C:\Apps\Unicode 软件\App.exe',
          TargetPlatform.windows,
        ),
        (
          InstalledLaunchKind.macBundle,
          "/Applications/O'Brien 软件.app",
          TargetPlatform.macOS,
        ),
        (
          InstalledLaunchKind.linuxDesktopEntry,
          "/home/local/.local/share/applications/O'Brien.desktop",
          TargetPlatform.linux,
        ),
        (
          InstalledLaunchKind.linuxExecutable,
          '/home/local/Applications/Portable App.AppImage',
          TargetPlatform.linux,
        ),
      ];
      handle(null);
      for (final (kind, locator, platform) in cases) {
        final registered = target(kind, locator);
        final launcher = InstalledApplicationLauncher(
          resolve: (id) => id == registered.id ? registered : null,
          channel: channel,
          platformOverride: platform,
          targetExists: (_) async => true,
        );
        await launcher.launch(registered.id);
        expect(calls.last.method, 'launch');
        expect(calls.last.arguments, {'kind': kind.name, 'locator': locator});
      }
    },
  );
  test(
    'unknown malformed unavailable wrong-platform and identity-spoof targets never reach native',
    () async {
      handle(null);
      final registered = target(
        InstalledLaunchKind.macBundle,
        '/Applications/Example.app',
      );
      final missing = InstalledApplicationLauncher(
        resolve: (_) => null,
        channel: channel,
        platformOverride: TargetPlatform.macOS,
        targetExists: (_) async => true,
      );
      await expectLater(missing.launch(registered.id), throwsStateError);
      await expectLater(missing.launch('../app'), throwsStateError);
      final wrong = InstalledApplicationLauncher(
        resolve: (_) => registered,
        channel: channel,
        platformOverride: TargetPlatform.windows,
        targetExists: (_) async => true,
      );
      await expectLater(wrong.launch(registered.id), throwsStateError);
      final removed = InstalledApplicationLauncher(
        resolve: (_) => registered.copyWith(available: false),
        channel: channel,
        platformOverride: TargetPlatform.macOS,
        targetExists: (_) async => true,
      );
      await expectLater(removed.launch(registered.id), throwsStateError);
      final stale = InstalledApplicationLauncher(
        resolve: (_) => registered,
        channel: channel,
        platformOverride: TargetPlatform.macOS,
        targetExists: (_) async => false,
      );
      await expectLater(stale.launch(registered.id), throwsStateError);
      final spoof = InstalledApplicationLauncher(
        resolve: (_) => registered,
        channel: channel,
        platformOverride: TargetPlatform.macOS,
        targetExists: (_) async => true,
      );
      await expectLater(
        spoof.launch('installed.${'f' * 32}'),
        throwsStateError,
      );
      expect(calls, isEmpty);
    },
  );
  test(
    'a registry removal during existence validation prevents native dispatch',
    () async {
      handle(null);
      final registered = target(
        InstalledLaunchKind.linuxExecutable,
        '/opt/Example.AppImage',
      );
      var live = true;
      final launcher = InstalledApplicationLauncher(
        resolve: (_) => live ? registered : null,
        channel: channel,
        platformOverride: TargetPlatform.linux,
        targetExists: (_) async {
          live = false;
          return true;
        },
      );
      await expectLater(launcher.launch(registered.id), throwsStateError);
      expect(calls, isEmpty);
    },
  );
  test(
    'native rejection and timeout never become activation success',
    () async {
      final registered = target(
        InstalledLaunchKind.windowsAppId,
        'Example!Main',
      );
      final launcher = InstalledApplicationLauncher(
        resolve: (_) => registered,
        channel: channel,
        platformOverride: TargetPlatform.windows,
        timeout: const Duration(milliseconds: 30),
      );
      handle((_) async => false);
      await expectLater(launcher.launch(registered.id), throwsStateError);
      final delayed = Completer<Object?>();
      handle((_) => delayed.future);
      await expectLater(
        launcher.launch(registered.id),
        throwsA(isA<TimeoutException>()),
      );
      delayed.complete(true);
    },
  );
  test('late registered icon results cannot escape removal', () async {
    final registered = target(InstalledLaunchKind.windowsAppId, 'Example!Main');
    var live = true;
    final response = Completer<Object?>();
    handle((_) => response.future);
    final launcher = InstalledApplicationLauncher(
      resolve: (_) => live ? registered : null,
      channel: channel,
      platformOverride: TargetPlatform.windows,
    );
    final pending = launcher.icon(registered.id);
    await Future<void>.delayed(Duration.zero);
    live = false;
    response.complete(
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
    );
    expect(await pending, isNull);
  });
  test(
    'registered native icons ignore executable text and keep PNG validation/cache bounds',
    () async {
      final registered = target(
        InstalledLaunchKind.windowsAppId,
        'Example!Main',
      );
      var live = true;
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      handle((_) async => bytes);
      final icons = NativeAppIconService(
        platformOverride: TargetPlatform.windows,
        installedChannel: channel,
        registeredTargetResolver: (_) => live ? registered : null,
      );
      final app = RemoteApplication(
        id: registered.id,
        name: 'Example',
        icon: 'apps',
        executable: 'ignored raw text\nnot a launch parameter',
        layoutId: installedLaunchOnlyLayoutId,
        launchOnly: true,
        detected: true,
      );
      expect(await icons.getNativeIcon(app), bytes);
      expect(await icons.getNativeIcon(app), bytes);
      expect(calls.length, 1);
      live = false;
      expect(await icons.getNativeIcon(app), isNull);
      expect(calls.length, 1);
    },
  );
  test(
    'dynamic button launch uses registry ID instead of placeholder executable',
    () async {
      final registered = target(
        InstalledLaunchKind.windowsAppId,
        'Example!Main',
      );
      final actual = const MethodChannel('lumiakeys/installed_apps');
      final native = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(actual, (call) async {
            native.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(actual, null),
      );
      final actions = DesktopActions(platformOverride: TargetPlatform.windows)
        ..registeredTargetResolver = (_) => registered;
      final app = RemoteApplication(
        id: registered.id,
        name: 'Example',
        icon: 'apps',
        executable: 'Desktop-managed',
        layoutId: installedLaunchOnlyLayoutId,
        launchOnly: true,
        detected: true,
      );
      final base = DesktopManifest.regularStarter();
      final manifest = base.copyWith(
        layouts: [...base.layouts, installedLaunchOnlyLayout],
        applications: [...base.applications, app],
      );
      await actions.executeButton(
        RemoteShortcutButton(
          id: 'user.launch',
          name: 'Open',
          icon: 'apps',
          targetType: RemoteTargetType.launchApplication,
          target: app.id,
        ),
        manifest,
      );
      expect(native.single.arguments, {
        'kind': 'windowsAppId',
        'locator': 'Example!Main',
      });
    },
  );
  test(
    'registry/filesystem/native errors do not expose private locators',
    () async {
      const sensitive = '/private/account/file token';
      final registered = target(
        InstalledLaunchKind.windowsAppId,
        'Example!Main',
      );
      final broken = InstalledApplicationLauncher(
        resolve: (_) => throw StateError(sensitive),
        channel: channel,
        platformOverride: TargetPlatform.windows,
      );
      expect(broken.registeredTarget(registered.id), isNull);
      final denied = InstalledApplicationLauncher(
        resolve: (_) => registered,
        channel: channel,
        platformOverride: TargetPlatform.windows,
        targetExists: (_) async =>
            throw const FileSystemException(sensitive, sensitive),
      );
      try {
        await denied.launch(registered.id);
        fail('Expected rejection');
      } catch (error) {
        expect(error.toString(), isNot(contains(sensitive)));
      }
      handle(
        (_) async =>
            throw PlatformException(code: 'failed', message: sensitive),
      );
      final native = InstalledApplicationLauncher(
        resolve: (_) => registered,
        channel: channel,
        platformOverride: TargetPlatform.windows,
      );
      try {
        await native.launch(registered.id);
        fail('Expected rejection');
      } catch (error) {
        expect(error.toString(), isNot(contains(sensitive)));
      }
    },
  );
  test(
    'slot removal or auto-launch revocation during existence check prevents native launch',
    () async {
      final registered = target(
        InstalledLaunchKind.windowsAppId,
        'Example!Main',
      );
      for (final revokeSlot in [true, false]) {
        calls.clear();
        handle(null);
        var selected = true, enabled = true;
        final checked = Completer<bool>();
        final launcher = InstalledApplicationLauncher(
          resolve: (_) => registered,
          channel: channel,
          platformOverride: TargetPlatform.windows,
          targetExists: (_) => checked.future,
        );
        final pending = launcher.launch(
          registered.id,
          authorize: (_) => selected && enabled,
        );
        if (revokeSlot) {
          selected = false;
        } else {
          enabled = false;
        }
        checked.complete(true);
        await expectLater(pending, throwsStateError);
        expect(calls, isEmpty);
      }
    },
  );
}
