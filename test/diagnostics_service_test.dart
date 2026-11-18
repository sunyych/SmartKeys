import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/diagnostics/diagnostics_service.dart';
import 'package:smart_keys/diagnostics/diagnostics_store.dart';
import 'package:smart_keys/diagnostics/diagnostics_uploader.dart';
import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/private_image_store.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/data/shortcut_usage_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/orientation_service.dart';
import 'package:smart_keys/services/power_brightness_service.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'test_support.dart';

final metadata = DiagnosticMetadata(
  appVersion: '1.6.0',
  appBuild: 8,
  edition: DiagnosticEdition.full,
  platform: DiagnosticPlatform.android,
);
const hostile =
    'CTRL+C clipboard SECRET transcript C:\\private\\my-secret.txt Bearer token-secret https://192.168.1.9/?password=secret';
Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), true);
}

class DelayedStore extends MemoryDiagnosticsStore {
  Completer<void>? grantEntered, releaseGrant;
  bool blockClearRevocation = false;
  @override
  Future<void> writeConsent(Map<String, Object?> value) async {
    if (value['choice'] == 'allowSharing' && releaseGrant != null) {
      grantEntered!.complete();
      await releaseGrant!.future;
      releaseGrant = null;
    }
    await super.writeConsent(value);
  }
}

class BrokenReadStore extends MemoryDiagnosticsStore {
  @override
  Future<Object?> readJournal() async => throw StateError(hostile);
}

class DelayedJournalStore extends MemoryDiagnosticsStore {
  Completer<void>? entered, release;
  @override
  Future<void> writeJournal(Map<String, Object?> value) async {
    if (release != null) {
      entered!.complete();
      await release!.future;
      release = null;
    }
    await super.writeJournal(value);
  }
}

class QueuedJournalStore extends MemoryDiagnosticsStore {
  bool block = false;
  final gates = <Completer<void>>[];
  @override
  Future<void> writeJournal(Map<String, Object?> value) async {
    if (block) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    await super.writeJournal(value);
  }
}

class FailingActions extends RecordingCompanionService {
  bool fail = false;
  @override
  Future<void> executeRemote(RemoteActionRequest request) async {
    if (fail) throw StateError(hostile);
    await super.executeRemote(request);
  }
}

class BrokenConfig extends MemoryConfigRepository {
  BrokenConfig() : super(testConfig());
  @override
  Future<void> save(AppConfig config) async => throw StateError(hostile);
}

void main() {
  late HttpServer server;
  late MemoryDiagnosticsStore store;
  late DiagnosticsService service;
  late List<Map<String, dynamic>> bodies;
  Future<void> Function(HttpRequest, Map<String, dynamic>)? respond;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    store = MemoryDiagnosticsStore();
    bodies = [];
    respond = null;
    server.listen((request) async {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      bodies.add(body);
      if (respond != null) {
        await respond!(request, body);
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'acceptedIds': [
            for (final event in body['events'] as List) event['id'],
          ],
        }),
      );
      await request.response.close();
    });
    service = DiagnosticsService(
      metadata: metadata,
      store: store,
      uploader: DiagnosticsUploader(
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/v1/diagnostics/errors',
        ),
        allowLoopbackHttp: true,
      ),
      retryDelays: const [Duration(milliseconds: 10)],
    );
    await service.initialize();
  });
  tearDown(() async {
    service.dispose();
    await server.close(force: true);
  });
  test(
    'default/local state never uploads; allow excludes all prior epochs',
    () async {
      service.record(DiagnosticCode.runtimeFailure);
      await service.flush();
      expect(bodies, isEmpty);
      await service.setSharing(false);
      service.record(DiagnosticCode.connectionUnavailable);
      await service.flush();
      expect(bodies, isEmpty);
      expect(await service.setSharing(true), true);
      service.record(DiagnosticCode.iconDownloadFailed);
      await until(() => bodies.length == 1);
      await until(() => !service.sending);
      expect((bodies.single['events'] as List).map((e) => e['code']), [
        'iconDownloadFailed',
      ]);
      expect(bodies.single.keys, ['schemaVersion', 'events']);
      final wire = (bodies.single['events'] as List).single as Map;
      expect(wire.keys.toSet(), {
        'id',
        'occurredAtMs',
        'lastOccurredAtMs',
        'appVersion',
        'appBuild',
        'edition',
        'platform',
        'code',
        'repeatCount',
      });
      expect(wire.containsKey('consentEpoch'), false);
      await service.setSharing(false);
      service.record(DiagnosticCode.runtimeFailure);
      await service.setSharing(true);
      await service.flush();
      expect(bodies, hasLength(1));
    },
  );
  test(
    'empty/subset acknowledgements use finite retry budget even during sustained errors',
    () async {
      respond = (request, body) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"acceptedIds":[]}');
        await request.response.close();
      };
      await service.setSharing(true);
      service.record(DiagnosticCode.connectionUnavailable);
      await until(() => bodies.length == 2 && !service.sending);
      for (var i = 0; i < 8; i++) {
        service.record(DiagnosticCode.connectionUnavailable);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(bodies, hasLength(2));
      expect(service.uploadError, isNotNull);
      await service.retrySharing();
      expect(bodies, hasLength(3));
      await service.setSharing(false);
    },
  );
  test(
    'revoke cancels in-flight request and prevents retry/backfill',
    () async {
      final received = Completer<void>();
      respond = (request, body) async {
        if (!received.isCompleted) received.complete();
      };
      await service.setSharing(true);
      service.record(DiagnosticCode.runtimeFailure);
      await received.future;
      final off = service.setSharing(false);
      expect(service.sharing, false);
      expect(service.sending, false);
      await off;
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(bodies, hasLength(1));
      respond = null;
      await service.setSharing(true);
      await service.flush();
      expect(bodies, hasLength(1));
    },
  );
  test(
    'grant vs revoke and clear are serialized and no old grant erases tombstone',
    () async {
      final delayed = DelayedStore()
        ..grantEntered = Completer<void>()
        ..releaseGrant = Completer<void>();
      service.dispose();
      service = DiagnosticsService(metadata: metadata, store: delayed);
      await service.initialize();
      final grant = service.setSharing(true);
      await delayed.grantEntered!.future;
      final revoke = service.setSharing(false);
      expect(service.sharing, false);
      delayed.releaseGrant!.complete();
      await grant;
      await revoke;
      expect(delayed.revoked, true);
      expect(service.sharing, false);
      final restart = DiagnosticsService(metadata: metadata, store: delayed);
      await restart.initialize();
      expect(restart.sharing, false);
      restart.dispose();
      delayed.grantEntered = Completer<void>();
      delayed.releaseGrant = Completer<void>();
      final secondGrant = service.setSharing(true);
      await delayed.grantEntered!.future;
      final clear = service.clear();
      delayed.releaseGrant!.complete();
      await secondGrant;
      await clear;
      expect(service.sharing, false);
      expect(delayed.revoked, true);
    },
  );
  test(
    'durable tombstone survives consent save failure and all write failures remain local',
    () async {
      await service.setSharing(true);
      store.failConsent = true;
      expect(await service.setSharing(false), true);
      expect(service.status, contains('revocation is saved'));
      final restart = DiagnosticsService(metadata: metadata, store: store);
      await restart.initialize();
      expect(restart.sharing, false);
      restart.dispose();
      store.failTombstone = true;
      expect(await service.setSharing(false), false);
      expect(service.status, contains('session'));
      expect(await service.setSharing(true), false);
      expect(service.sharing, false);
    },
  );
  test(
    'journal read/write failure fail closed and never sends an unsaved error',
    () async {
      await service.setSharing(true);
      store.failJournal = true;
      service.record(DiagnosticCode.runtimeFailure);
      await until(() => service.storageError != null);
      await service.flush();
      expect(service.sharing, false);
      expect(bodies, isEmpty);
      final broken = BrokenReadStore()
        ..consent = {
          'schemaVersion': 1,
          'choice': 'allowSharing',
          'epoch': 1,
          'retentionDays': 30,
        };
      final restart = DiagnosticsService(metadata: metadata, store: broken);
      await restart.initialize();
      expect(restart.sharing, false);
      expect(restart.status, contains('remain local'));
      restart.dispose();
    },
  );
  test(
    'an in-flight journal write cannot leak an unpersisted event through manual flush',
    () async {
      final delayed = DelayedJournalStore();
      service.dispose();
      service = DiagnosticsService(
        metadata: metadata,
        store: delayed,
        uploader: DiagnosticsUploader(
          endpoint: Uri.parse(
            'http://127.0.0.1:${server.port}/v1/diagnostics/errors',
          ),
          allowLoopbackHttp: true,
        ),
      );
      await service.initialize();
      await service.setSharing(true);
      delayed.entered = Completer<void>();
      delayed.release = Completer<void>();
      service.record(DiagnosticCode.runtimeFailure);
      await delayed.entered!.future;
      final flush = service.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bodies, isEmpty);
      delayed.failJournal = true;
      delayed.release!.complete();
      await flush;
      expect(service.sharing, false);
      expect(bodies, isEmpty);
    },
  );
  test(
    'startup removes expired records from durable storage without uploading',
    () async {
      final earlier = DateTime.now().subtract(const Duration(days: 8));
      final old = ErrorJournal(metadata: metadata, clock: () => earlier)
        ..capture(DiagnosticCode.runtimeFailure, consentEpoch: 1);
      store.consent = {
        'schemaVersion': 1,
        'choice': 'allowSharing',
        'epoch': 1,
        'retentionDays': 7,
      };
      store.journal = {
        'schemaVersion': 1,
        'journal': old.toLocalJson(),
        'uploadedCounts': <String, int>{},
      };
      service.dispose();
      service = DiagnosticsService(metadata: metadata, store: store);
      await service.initialize();
      expect(service.events, isEmpty);
      expect(((store.journal as Map)['journal'] as Map)['events'], isEmpty);
      expect(bodies, isEmpty);
    },
  );
  test(
    'A saved while B is still writing cannot automatically upload B',
    () async {
      final delayed = QueuedJournalStore();
      service.dispose();
      service = DiagnosticsService(
        metadata: metadata,
        store: delayed,
        uploader: DiagnosticsUploader(
          endpoint: Uri.parse(
            'http://127.0.0.1:${server.port}/v1/diagnostics/errors',
          ),
          allowLoopbackHttp: true,
        ),
      );
      await service.initialize();
      await service.setSharing(true);
      delayed.block = true;
      service.record(DiagnosticCode.connectionTimeout);
      await until(() => delayed.gates.length == 1);
      service.record(DiagnosticCode.iconDownloadFailed);
      delayed.gates.first.complete();
      await until(() => delayed.gates.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bodies, isEmpty);
      delayed.failJournal = true;
      delayed.gates.last.complete();
      await until(() => !service.sharing);
      expect(bodies, isEmpty);
    },
  );
  test(
    'partial/duplicate acknowledgement is rejected by real HTTP uploader',
    () async {
      final journal = ErrorJournal(metadata: metadata)
        ..capture(DiagnosticCode.connectionTimeout)
        ..capture(DiagnosticCode.iconDownloadFailed);
      respond = (request, body) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'acceptedIds': [(body['events'] as List).first['id']],
          }),
        );
        await request.response.close();
      };
      await expectLater(
        service.uploader.send(journal.events),
        throwsFormatException,
      );
    },
  );
  test(
    'file store round trip persists only fixed fields and restores local retention',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'diagnostics-file-',
      );
      final files = FileDiagnosticsStore(directory: () async => directory);
      final local = DiagnosticsService(metadata: metadata, store: files);
      await local.initialize();
      await local.setSharing(false);
      await local.setRetentionDays(7);
      local.record(DiagnosticCode.runtimeFailure);
      await local.flush();
      final persisted = jsonEncode(await files.readJournal());
      expect(persisted, contains('runtimeFailure'));
      expect(persisted, isNot(contains(hostile)));
      local.dispose();
      final restart = DiagnosticsService(metadata: metadata, store: files);
      await restart.initialize();
      expect(restart.events, hasLength(1));
      expect(restart.retentionDays, 7);
      expect(restart.sharing, false);
      restart.dispose();
      await directory.delete(recursive: true);
    },
  );
  test(
    'hourly maintenance expires disk records while idle and never starts upload',
    () async {
      var now = DateTime.now();
      final journal = ErrorJournal(metadata: metadata, clock: () => now)
        ..capture(DiagnosticCode.runtimeFailure, consentEpoch: 1);
      store.consent = {
        'schemaVersion': 1,
        'choice': 'allowSharing',
        'epoch': 1,
        'retentionDays': 7,
      };
      store.journal = {
        'schemaVersion': 1,
        'journal': journal.toLocalJson(),
        'uploadedCounts': <String, int>{},
      };
      service.dispose();
      service = DiagnosticsService(
        metadata: metadata,
        store: store,
        clock: () => now,
        maintenanceInterval: const Duration(milliseconds: 5),
        uploader: DiagnosticsUploader(
          endpoint: Uri.parse(
            'http://127.0.0.1:${server.port}/v1/diagnostics/errors',
          ),
          allowLoopbackHttp: true,
        ),
      );
      await service.initialize();
      now = now.add(const Duration(days: 8));
      await until(
        () => (((store.journal as Map)['journal'] as Map)['events'] as List)
            .isEmpty,
      );
      expect(bodies, isEmpty);
      service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(bodies, isEmpty);
      service = DiagnosticsService(
        metadata: metadata,
        store: MemoryDiagnosticsStore(),
      );
      await service.initialize();
    },
  );
  test(
    'clear and retention persist; absent metadata/endpoint cannot upload',
    () async {
      await service.setSharing(true);
      await service.setRetentionDays(7);
      service.record(DiagnosticCode.runtimeFailure);
      await service.clear();
      expect(service.events, isEmpty);
      expect(service.retentionDays, 7);
      final local = DiagnosticsService(
        metadata: DiagnosticMetadata(
          appVersion: null,
          appBuild: null,
          edition: DiagnosticEdition.full,
          platform: DiagnosticPlatform.ios,
        ),
        store: MemoryDiagnosticsStore(),
      );
      await local.initialize();
      expect(await local.setSharing(true), false);
      local.record(DiagnosticCode.runtimeFailure);
      await local.flush();
      expect(local.sharing, false);
      local.dispose();
      expect(
        () => DiagnosticsUploader(
          endpoint: Uri.parse('http://192.168.1.2/v1/diagnostics/errors'),
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'hostile real action/config errors become fixed codes; successful inputs create zero errors',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'diagnostic-input-',
      );
      final remote = FailingActions();
      final controller = AppController(
        repository: BrokenConfig(),
        templates: ProfileTemplateRepository(),
        hid: RecordingHidService(),
        companion: remote,
        orientationService: RecordingOrientationService(),
        imageStore: PrivateImageStore(
          documentsDirectory: () async => directory,
        ),
        powerBrightnessService: RecordingPowerBrightnessService(),
        shortcutUsage: MemoryShortcutUsageRepository(),
        reportDiagnostic: service.record,
      );
      await controller.initialize();
      final layout = DesktopManifest.regularStarter().layouts.first;
      await controller.executeRemoteButton(layout.buttons.first);
      expect(service.events, isEmpty);
      await expectLater(
        controller.setBeginnerMode(!controller.config.preferences.beginnerMode),
        throwsStateError,
      );
      remote.fail = true;
      await expectLater(
        controller.executeRemoteButton(layout.buttons.first),
        throwsStateError,
      );
      await expectLater(
        controller.launchRemoteApplication(
          DesktopManifest.regularStarter().applications.first,
        ),
        throwsStateError,
      );
      await service.setSharing(true);
      await expectLater(
        controller.executeRemoteButton(layout.buttons.first),
        throwsStateError,
      );
      await until(() => bodies.isNotEmpty);
      await until(() => !service.sending);
      final serialized = '${jsonEncode(store.journal)} ${jsonEncode(bodies)}';
      for (final secret in [
        'CTRL+C',
        'clipboard',
        'SECRET',
        'transcript',
        'my-secret',
        'token-secret',
        '192.168.1.9',
        'password',
      ]) {
        expect(serialized, isNot(contains(secret)));
      }
      expect(
        service.events.map((e) => e.code),
        containsAll([
          DiagnosticCode.shortcutDeliveryFailed,
          DiagnosticCode.applicationActivationFailed,
          DiagnosticCode.configurationSaveFailed,
        ]),
      );
      controller.dispose();
      await directory.delete(recursive: true);
    },
  );
}
