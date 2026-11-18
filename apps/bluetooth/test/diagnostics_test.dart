import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/main.dart';
import 'package:lumiakey_bluetooth_lite/local_diagnostics.dart';
import 'package:lumiakey_bluetooth_lite/local_settings.dart';
import 'package:lumiakey_bluetooth_lite/runtime_error_hooks.dart';
import 'package:lumiakey_bluetooth_lite/icons/builtin_icon_catalog.g.dart';

const channel = MethodChannel('smart_keys/hid');
const secret =
    'Bearer private-token CTRL+C clipboard /private/user/file 192.168.1.4 transcript';
const connected = {
  'status': 'connected',
  'activeHost': {'id': 'pc', 'name': 'PC', 'address': 'AA:BB:CC:DD:EE:FF'},
  'pairedHosts': [],
};
LiteDiagnostics local() {
  final diagnostics = LiteDiagnostics(
    metadataLoader: () async => {'appVersion': '1.1.7', 'appBuild': 117},
  );
  addTearDown(diagnostics.dispose);
  return diagnostics;
}

Future<LiteController> inputController(LiteDiagnostics diagnostics) async {
  final controller = LiteController(diagnostics: diagnostics);
  addTearDown(controller.dispose);
  await controller.initialize();
  controller.setLandscape(true);
  controller.setControlsVisible(true);
  return controller;
}

const diagnosticTestKey = LocalShortcut(
  title: 'Copy',
  keyCode: 'C',
  modifiers: ['LEFT_CTRL'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'actual native metadata is read dynamically and sanitized logs survive reload',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return {'appVersion': '9.7.3', 'appBuild': 973};
          });
      final diagnostics = LiteDiagnostics();
      addTearDown(diagnostics.dispose);
      await diagnostics.initialize();
      expect(calls, ['getAppMetadata']);
      expect(diagnostics.journal.metadata.appVersion, '9.7.3');
      expect(diagnostics.journal.metadata.appBuild, 973);
      await diagnostics.capture(DiagnosticCode.bluetoothInputFailed);
      await diagnostics.setRetentionDays(7);
      final reloaded = local();
      await reloaded.initialize();
      expect(reloaded.journal.retention.inDays, 7);
      expect(
        reloaded.journal.events.single.code,
        DiagnosticCode.bluetoothInputFailed,
      );
      expect(
        () => reloaded.journal.events.single.toUploadJson(),
        throwsStateError,
      );
      await reloaded.clear();
      expect(reloaded.journal.events, isEmpty);
    },
  );
  test('missing metadata stays explicitly local and unverified', () async {
    final diagnostics = LiteDiagnostics(
      metadataLoader: () async => throw StateError(secret),
    );
    addTearDown(diagnostics.dispose);
    await diagnostics.initialize();
    await diagnostics.capture(DiagnosticCode.platformUnavailable);
    expect(diagnostics.journal.metadata.verified, isFalse);
    expect(diagnostics.journal.events.single.metadata.appVersion, isNull);
    expect(
      () => diagnostics.journal.events.single.toUploadJson(),
      throwsStateError,
    );
    expect(
      jsonEncode(diagnostics.journal.toLocalJson()),
      isNot(contains(secret)),
    );
  });
  test(
    'storage failures keep a bounded in-memory journal without recursive errors',
    () async {
      final diagnostics = LiteDiagnostics(
        metadataLoader: () async => {'appVersion': '1.1.0', 'appBuild': 2},
        preferences: () async => throw StateError(secret),
      );
      addTearDown(diagnostics.dispose);
      await diagnostics.capture(DiagnosticCode.configurationSaveFailed);
      expect(diagnostics.storageFailed, isTrue);
      expect(diagnostics.journal.events.length, 1);
      expect(
        jsonEncode(diagnostics.journal.toLocalJson()),
        isNot(contains('private-token')),
      );
    },
  );
  test('queued local captures preserve every repeated occurrence', () async {
    final diagnostics = local();
    await Future.wait(
      List.generate(
        12,
        (_) => diagnostics.capture(DiagnosticCode.runtimeFailure),
      ),
    );
    expect(diagnostics.journal.events.single.repeatCount, 12);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(LiteDiagnostics.storageKey)!;
    expect(raw, isNot(contains('consentEpoch":1')));
    final restored = local();
    await restored.initialize();
    expect(restored.journal.events.single.repeatCount, 12);
  });
  test(
    'global Flutter/platform hooks capture only fixed codes and preserve delegates',
    () async {
      final diagnostics = local();
      await diagnostics.initialize();
      final oldFlutter = FlutterError.onError,
          oldPlatform = PlatformDispatcher.instance.onError;
      var flutterCalls = 0, platformCalls = 0;
      FlutterError.onError = (_) => flutterCalls++;
      PlatformDispatcher.instance.onError = (_, _) {
        platformCalls++;
        return true;
      };
      final hooks = LiteRuntimeErrorHooks(diagnostics)..install();
      try {
        FlutterError.onError!(
          FlutterErrorDetails(
            exception: StateError(secret),
            stack: StackTrace.fromString(secret),
          ),
        );
        expect(
          PlatformDispatcher.instance.onError!(
            StateError(secret),
            StackTrace.fromString(secret),
          ),
          isTrue,
        );
        await diagnostics.settled;
        expect(flutterCalls, 1);
        expect(platformCalls, 1);
        expect(diagnostics.journal.events.single.repeatCount, 2);
        expect(
          diagnostics.journal.events.single.code,
          DiagnosticCode.runtimeFailure,
        );
        expect(
          jsonEncode(diagnostics.journal.toLocalJson()),
          isNot(contains('private-token')),
        );
      } finally {
        hooks.restore();
        FlutterError.onError = oldFlutter;
        PlatformDispatcher.instance.onError = oldPlatform;
      }
    },
  );
  test(
    'successful keyboard and pointer input create no diagnostic events',
    () async {
      final diagnostics = local();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async =>
                call.method == 'refreshPairedHosts' ? connected : null,
          );
      final controller = await inputController(diagnostics);
      expect(await controller.executeShortcut(diagnosticTestKey), true);
      expect(await controller.movePointer(const Offset(30, 10)), true);
      await diagnostics.settled;
      expect(diagnostics.journal.events, isEmpty);
    },
  );
  test(
    'a hostile native failure reaches only the fixed safe journal category',
    () async {
      final diagnostics = local();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'sendStep') {
              throw PlatformException(
                code: secret,
                message: secret,
                details: secret,
              );
            }
            return call.method == 'refreshPairedHosts' ? connected : null;
          });
      final controller = await inputController(diagnostics);
      expect(await controller.executeShortcut(diagnosticTestKey), false);
      await diagnostics.settled;
      expect(
        diagnostics.journal.events.single.code,
        DiagnosticCode.bluetoothInputFailed,
      );
      final raw = (await SharedPreferences.getInstance()).getString(
        LiteDiagnostics.storageKey,
      )!;
      for (final forbidden in [
        'private-token',
        'CTRL+C',
        'clipboard',
        '/private/user',
        '192.168.1.4',
        'transcript',
      ]) {
        expect(raw, isNot(contains(forbidden)));
      }
    },
  );
  test(
    'repeated native error snapshots do not turn refreshes into new errors',
    () async {
      final diagnostics = local();
      var failed = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'refreshPairedHosts'
                ? {
                    ...connected,
                    'error': failed ? 'fixture connection failure' : null,
                  }
                : null,
          );
      final controller = await inputController(diagnostics);
      await diagnostics.settled;
      expect(diagnostics.journal.events.single.repeatCount, 1);
      await controller.refreshPairedHosts();
      await diagnostics.settled;
      expect(diagnostics.journal.events.single.repeatCount, 1);
      failed = false;
      await controller.refreshPairedHosts();
      failed = true;
      await controller.refreshPairedHosts();
      await diagnostics.settled;
      expect(diagnostics.journal.events.single.repeatCount, 2);
    },
  );
  test('a native callback plus failed command records one error', () async {
    final diagnostics = local();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'sendStep') {
            final delivered = Completer<void>();
            ServicesBinding.instance.channelBuffers.push(
              'smart_keys/hid',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('connectionSnapshotChanged', {
                  ...connected,
                  'error': secret,
                }),
              ),
              (_) => delivered.complete(),
            );
            await delivered.future;
            throw PlatformException(code: secret, message: secret);
          }
          return call.method == 'refreshPairedHosts' ? connected : null;
        });
    final controller = await inputController(diagnostics);
    expect(await controller.executeShortcut(diagnosticTestKey), false);
    await diagnostics.settled;
    expect(diagnostics.journal.events.length, 1);
    expect(
      diagnostics.journal.events.single.code,
      DiagnosticCode.bluetoothInputFailed,
    );
    expect(diagnostics.journal.events.single.repeatCount, 1);
  });
  test(
    'startup persistence removes expired JSON without a new error',
    () async {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 8));
      final journal = ErrorJournal(
        metadata: DiagnosticMetadata(
          appVersion: '1.1.0',
          appBuild: 2,
          edition: DiagnosticEdition.lite,
          platform: DiagnosticPlatform.android,
        ),
        clock: () => old,
      )..capture(DiagnosticCode.runtimeFailure);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LiteDiagnostics.storageKey,
        jsonEncode({'retentionDays': 7, 'journal': journal.toLocalJson()}),
      );
      final diagnostics = local();
      await diagnostics.initialize();
      expect(diagnostics.journal.events, isEmpty);
      final persisted = jsonDecode(
        prefs.getString(LiteDiagnostics.storageKey)!,
      );
      expect(persisted['journal']['events'], isEmpty);
      expect(
        prefs.getString(LiteDiagnostics.storageKey),
        isNot(contains('runtimeFailure')),
      );
    },
  );
  testWidgets('hourly cleanup persists expiry while the app remains open', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 17);
    final diagnostics = LiteDiagnostics(
      clock: () => now,
      metadataLoader: () async => {'appVersion': '1.1.0', 'appBuild': 2},
    );
    addTearDown(diagnostics.dispose);
    await diagnostics.capture(DiagnosticCode.runtimeFailure);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(LiteDiagnostics.storageKey),
      contains('runtimeFailure'),
    );
    now = now.add(const Duration(days: 31));
    await tester.pump(const Duration(hours: 1));
    await diagnostics.settled;
    expect(
      prefs.getString(LiteDiagnostics.storageKey),
      isNot(contains('runtimeFailure')),
    );
    expect(diagnostics.journal.events, isEmpty);
    diagnostics.dispose();
  });
  test('all fifty bundled PNGs decode offline', () async {
    expect(builtinIconCatalog.length, 50);
    expect(builtinIconCatalog.map((e) => e.id).toSet().length, 50);
    for (final entry in builtinIconCatalog) {
      final bytes = (await rootBundle.load(
        entry.assetPath,
      )).buffer.asUint8List();
      expect(bytes.length, lessThanOrEqualTo(65536));
      final decoded = img.decodePng(bytes);
      expect(decoded, isNotNull, reason: entry.id);
      expect(decoded!.width, 256);
      expect(decoded.height, 256);
    }
  });
  testWidgets(
    'offline library searches IDs/names/aliases and handles no matches',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LiteIconLibraryScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lite-icon-search')),
        'google-chrome',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lite-icon-chrome')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lite-icon-search')),
        'not-an-installed-app',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lite-icon-empty')), findsOneWidget);
    },
  );
}
