import 'dart:io';
import 'dart:math';

import 'package:smart_keys/data/shortcut_community_client.dart';

/// Explicit live-contract check for a locally running Rust community API.
/// Run with SMARTKEYS_TEST_SERVER_URL=http://127.0.0.1:PORT and dart run.
Future<void> main() async {
  final rawEndpoint = Platform.environment['SMARTKEYS_TEST_SERVER_URL'];
  if (rawEndpoint == null || rawEndpoint.isEmpty) {
    throw StateError('Set SMARTKEYS_TEST_SERVER_URL to a local API URL.');
  }
  final endpoint = Uri.parse(rawEndpoint);
  final loopback =
      endpoint.host == '127.0.0.1' ||
      endpoint.host == 'localhost' ||
      endpoint.host == '::1' ||
      endpoint.host == '[::1]';
  if (!loopback) {
    throw StateError('Live contract tests require a loopback host.');
  }

  final client = ShortcutCommunityClient(
    endpoint: rawEndpoint,
    allowLoopbackHttp: true,
  );
  const category = 'close_tab';
  const tag = 'design';
  const experience = 'intermediate';
  final globalBaseline = await _count(client, category);
  final taggedBaseline = await _count(client, category, tag: tag);
  final experiencedBaseline = await _count(
    client,
    category,
    experience: experience,
  );
  final combinedBaseline = await _count(
    client,
    category,
    tag: tag,
    experience: experience,
  );
  final batches = <CommunityPendingBatch>[];
  try {
    for (var i = 0; i < 3; i++) {
      final batch = CommunityPendingBatch(
        batchId: _randomHex(16),
        deleteToken: _randomHex(32),
        serverOrigin: client.serverOrigin!,
        items: const {category: 2},
        tag: tag,
        experience: experience,
        eventIds: const ['must-remain-local'],
      );
      await client.submit(batch);
      batches.add(batch);
    }
    final globalAfterThree = await _count(client, category);
    final taggedAfterThree = await _count(client, category, tag: tag);
    final experiencedAfterThree = await _count(
      client,
      category,
      experience: experience,
    );
    final combinedAfterThree = await _count(
      client,
      category,
      tag: tag,
      experience: experience,
    );
    _expect(
      globalAfterThree.count >= globalBaseline.count + 6,
      'three tagged batches should add six counts to the global ranking',
    );
    _expect(
      globalAfterThree.contributions >= globalBaseline.contributions + 3,
      'three tagged batches should add three global contributions',
    );
    _expect(
      taggedAfterThree.count >= taggedBaseline.count + 6,
      'three batches should add six counts to the selected tag',
    );
    _expect(
      taggedAfterThree.contributions >= taggedBaseline.contributions + 3,
      'three batches should add three contributions to the selected tag',
    );
    _expect(
      experiencedAfterThree.count >= experiencedBaseline.count + 6 &&
          experiencedAfterThree.contributions >=
              experiencedBaseline.contributions + 3,
      'experience filter should include the three matching batches',
    );
    _expect(
      combinedAfterThree.count >= combinedBaseline.count + 6 &&
          combinedAfterThree.contributions >=
              combinedBaseline.contributions + 3,
      'combined profession and experience filters should intersect correctly',
    );

    await client.submit(batches.first);
    final globalAfterRetry = await _count(client, category);
    final taggedAfterRetry = await _count(client, category, tag: tag);
    final combinedAfterRetry = await _count(
      client,
      category,
      tag: tag,
      experience: experience,
    );
    _expect(
      globalAfterRetry.count == globalAfterThree.count,
      'identical retry must not change the global count',
    );
    _expect(
      globalAfterRetry.contributions == globalAfterThree.contributions,
      'identical retry must not add a global contribution',
    );
    _expect(
      taggedAfterRetry.count == taggedAfterThree.count &&
          taggedAfterRetry.contributions == taggedAfterThree.contributions,
      'identical retry must not change the selected tag',
    );
    _expect(
      combinedAfterRetry.count == combinedAfterThree.count &&
          combinedAfterRetry.contributions == combinedAfterThree.contributions,
      'identical retry must not change combined filters',
    );

    await client.withdraw(
      batches.first.batchId,
      batches.first.deleteToken,
      origin: batches.first.serverOrigin,
    );
    await client.withdraw(
      batches.first.batchId,
      batches.first.deleteToken,
      origin: batches.first.serverOrigin,
    );
    for (final batch in batches.skip(1)) {
      await client.withdraw(
        batch.batchId,
        batch.deleteToken,
        origin: batch.serverOrigin,
      );
    }
    final globalAfterWithdrawn = await _count(client, category);
    final taggedAfterWithdrawn = await _count(client, category, tag: tag);
    final experiencedAfterWithdrawn = await _count(
      client,
      category,
      experience: experience,
    );
    final combinedAfterWithdrawn = await _count(
      client,
      category,
      tag: tag,
      experience: experience,
    );
    _expect(
      globalAfterWithdrawn.count == globalBaseline.count,
      'withdrawing test batches should restore the global pre-test count',
    );
    _expect(
      globalAfterWithdrawn.contributions == globalBaseline.contributions,
      'withdrawing test batches should restore the global pre-test contributions',
    );
    _expect(
      taggedAfterWithdrawn.count == taggedBaseline.count &&
          taggedAfterWithdrawn.contributions == taggedBaseline.contributions,
      'withdrawing test batches should restore the selected-tag baseline',
    );
    _expect(
      experiencedAfterWithdrawn.count == experiencedBaseline.count &&
          experiencedAfterWithdrawn.contributions ==
              experiencedBaseline.contributions,
      'withdrawal should restore the experience-filter baseline',
    );
    _expect(
      combinedAfterWithdrawn.count == combinedBaseline.count &&
          combinedAfterWithdrawn.contributions ==
              combinedBaseline.contributions,
      'withdrawal should restore the combined-filter baseline',
    );
    stdout.writeln(
      'Community API client contract passed; all test batches withdrawn.',
    );
  } finally {
    for (final batch in batches) {
      try {
        await client.withdraw(
          batch.batchId,
          batch.deleteToken,
          origin: batch.serverOrigin,
        );
      } on Object {
        // Already withdrawn (including the repeated DELETE check) or server unavailable.
      }
    }
  }
}

Future<({int count, int contributions})> _count(
  ShortcutCommunityClient client,
  String id, {
  String? tag,
  String? experience,
}) async {
  final ranking = await client.fetchRankings(
    'all',
    tag: tag,
    experience: experience,
  );
  final row = ranking.rows.where((row) => row.shortcutId == id).firstOrNull;
  return (count: row?.count ?? 0, contributions: row?.contributions ?? 0);
}

String _randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
