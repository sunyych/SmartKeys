import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/data/shortcut_community_client.dart';
import 'package:smart_keys/data/shortcut_community_store.dart';

void main() {
  group('ShortcutCommunityClient', () {
    test('empty endpoint is unconfigured and never starts a request', () async {
      final client = ShortcutCommunityClient(endpoint: '');
      expect(client.isConfigured, isFalse);
      await expectLater(
        client.fetchRankings('all'),
        throwsA(
          isA<CommunityServiceException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
    });

    test(
      'uploads only canonical ids and counts, then parses public ranking',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final seen = <Map<String, dynamic>>[];
        final serving = () async {
          await for (final request in server) {
            if (request.method == 'POST') {
              seen.add(
                jsonDecode(await utf8.decoder.bind(request).join())
                    as Map<String, dynamic>,
              );
              request.response.statusCode = 201;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'schema_version': 1,
                  'batch_id': 'a' * 32,
                  'status': 'accepted',
                }),
              );
            } else {
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'schema_version': 1,
                  'period': request.uri.queryParameters['period'],
                  'tag': request.uri.queryParameters['tag'],
                  'updated_at': '2026-10-21T12:00:00Z',
                  'rankings': [
                    {'shortcut_id': 'copy', 'count': 18, 'contributions': 4},
                  ],
                }),
              );
            }
            await request.response.close();
          }
        }();
        final client = ShortcutCommunityClient(
          endpoint: 'http://127.0.0.1:${server.port}',
          allowLoopbackHttp: true,
        );
        final batch = CommunityPendingBatch(
          batchId: 'a' * 32,
          deleteToken: 'b' * 64,
          serverOrigin: 'http://127.0.0.1:${server.port}',
          items: {'copy': 2},
          eventIds: const ['local-event-id', 'another-local-event-id'],
        );
        await client.submit(batch);
        final payload = seen.single;
        expect(payload.keys.toSet(), {
          'schema_version',
          'batch_id',
          'delete_token',
          'tag',
          'items',
        });
        expect(payload['items'], [
          {'shortcut_id': 'copy', 'count': 2},
        ]);
        expect(payload['tag'], isNull);
        expect(jsonEncode(payload), isNot(contains('local-event-id')));
        expect(jsonEncode(payload), isNot(contains('label')));
        expect(jsonEncode(payload), isNot(contains('timestamp')));
        final ranking = await client.fetchRankings('all');
        expect(ranking.rows.single.shortcutId, 'copy');
        expect(ranking.rows.single.count, 18);
        final tagged = await client.fetchRankings('30d', tag: 'design');
        expect(tagged.tag, 'design');
        expect(tagged.period, '30d');
        expect(
          () => client.fetchRankings('all', tag: 'unrestricted free text'),
          throwsArgumentError,
        );
        await server.close(force: true);
        await serving;
      },
    );

    test('rejects non-HTTPS endpoints outside explicit loopback testing', () {
      expect(
        () => ShortcutCommunityClient(endpoint: 'http://example.com'),
        throwsArgumentError,
      );
      expect(
        () => ShortcutCommunityClient(
          endpoint: 'http://example.com',
          allowLoopbackHttp: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => ShortcutCommunityClient(
          endpoint: 'https://user:secret@example.com',
        ),
        throwsArgumentError,
      );
    });

    test(
      'pending payload excludes event ids and persists for same-batch retry',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'smartkeys-community-',
        );
        try {
          const origin = 'https://ranking.example.test';
          final store = ShortcutCommunityStore(
            directory: directory,
            serverOrigin: origin,
          );
          await store.load();
          expect(store.sharingEnabled, isFalse);
          final batch = CommunityPendingBatch(
            batchId: 'c' * 32,
            deleteToken: 'd' * 64,
            serverOrigin: origin,
            items: {'paste': 3},
            eventIds: const ['secret-event-id'],
          );
          await store.savePending(batch);
          await expectLater(
            store.savePending(
              CommunityPendingBatch(
                batchId: 'e' * 32,
                deleteToken: 'f' * 64,
                serverOrigin: origin,
                items: {'copy': 1},
                eventIds: const ['other-event'],
              ),
            ),
            throwsStateError,
          );
          expect(store.pending?.batchId, batch.batchId);
          final restored = ShortcutCommunityStore(
            directory: directory,
            serverOrigin: origin,
          );
          await restored.load();
          expect(restored.pending?.batchId, batch.batchId);
          expect(restored.pending?.toPayload(), batch.toPayload());
          expect(restored.submittedEventIds, {'secret-event-id'});
          await restored.setSharingEnabled(true);
          expect(
            ShortcutCommunityStore(
              directory: directory,
              serverOrigin: origin,
            ).sharingEnabled,
            isFalse,
          );
          final secondRead = ShortcutCommunityStore(
            directory: directory,
            serverOrigin: origin,
          );
          await secondRead.load();
          expect(secondRead.sharingEnabled, isTrue);
          await secondRead.setSharingEnabled(false);
          expect(secondRead.pending?.batchId, batch.batchId);
          expect(secondRead.sharingEnabled, isFalse);
          await secondRead.setSharingEnabled(true);
          await secondRead.acknowledgePending();
          expect(secondRead.pending, isNull);
          expect(secondRead.receipts.single.batchId, batch.batchId);
          expect(secondRead.submittedEventIds, {'secret-event-id'});
          final changedEndpoint = ShortcutCommunityStore(
            directory: directory,
            serverOrigin: 'https://another-ranking.example.test',
          );
          await changedEndpoint.load();
          expect(changedEndpoint.sharingEnabled, isFalse);
          expect(changedEndpoint.receipts.single.serverOrigin, origin);
          await changedEndpoint.removeReceipt(batch.batchId);
          expect(changedEndpoint.submittedEventIds, {'secret-event-id'});
          final originalAfterWithdrawal = ShortcutCommunityStore(
            directory: directory,
            serverOrigin: origin,
          );
          await originalAfterWithdrawal.load();
          expect(originalAfterWithdrawal.receipts, isEmpty);
          expect(originalAfterWithdrawal.submittedEventIds, {
            'secret-event-id',
          });
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );

    test('rejects private or noncanonical batch data', () {
      expect(
        () => CommunityPendingBatch(
          batchId: 'a' * 32,
          deleteToken: 'b' * 64,
          serverOrigin: 'https://ranking.example.test',
          items: {'custom_key': 1},
          eventIds: const [],
        ),
        throwsArgumentError,
      );
      expect(
        CommunityPendingBatch(
          batchId: 'a' * 32,
          deleteToken: 'b' * 64,
          serverOrigin: 'https://ranking.example.test',
          items: {'copy': 1, 'paste': 2},
          eventIds: const [],
        ).toPayload().containsKey('event_ids'),
        isFalse,
      );
    });

    test(
      'clearing usage cancels pending retry but retains a withdrawal receipt',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'smartkeys-pending-clear-',
        );
        try {
          const origin = 'https://ranking.example.test/api';
          final store = ShortcutCommunityStore(
            directory: directory,
            serverOrigin: origin,
          );
          await store.load();
          final batch = CommunityPendingBatch(
            batchId: '7' * 32,
            deleteToken: '8' * 64,
            serverOrigin: origin,
            items: {'undo': 1},
            eventIds: const ['event-to-clear'],
          );
          await store.savePending(batch);
          await store.cancelPendingSubmission();
          expect(store.pending, isNull);
          expect(store.receipts.single.mayBeAccepted, isTrue);
          expect(store.submittedEventIds, {'event-to-clear'});
          final restored = ShortcutCommunityStore(
            directory: directory,
            serverOrigin: origin,
          );
          await restored.load();
          expect(restored.pending, isNull);
          expect(restored.receipts.single.batchId, batch.batchId);
          expect(restored.receipts.single.deleteToken, batch.deleteToken);
          expect(restored.submittedEventIds, {'event-to-clear'});
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );

    test('failed private writes roll back consent in memory', () async {
      final root = await Directory.systemTemp.createTemp(
        'smartkeys-store-error-',
      );
      try {
        final blocker = File(
          '${root.path}${Platform.pathSeparator}not-a-directory',
        );
        await blocker.writeAsString('file blocks directory creation');
        final store = ShortcutCommunityStore(
          directory: Directory(blocker.path),
          serverOrigin: 'https://ranking.example.test',
        );
        await store.load();
        await expectLater(
          store.setSharingEnabled(true),
          throwsA(isA<FileSystemException>()),
        );
        expect(store.sharingEnabled, isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
