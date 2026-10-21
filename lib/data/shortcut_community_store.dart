import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'shortcut_community_client.dart';

/// Private, device-local consent and submission receipts.
class ShortcutCommunityStore {
  ShortcutCommunityStore({
    required this._directory,
    required this.serverOrigin,
  });

  final Directory _directory;
  final String serverOrigin;
  File _fileFor(String origin) => File(
    '${_directory.path}${Platform.pathSeparator}community-sharing-${sha256.convert(utf8.encode(origin))}.json',
  );
  bool sharingEnabled = false;
  CommunityPendingBatch? pending;
  final List<CommunityReceipt> receipts = [];
  Future<void> _writes = Future<void>.value();

  Future<void> load() async {
    if (!await _directory.exists()) return;
    try {
      final entries = await _directory.list(followLinks: false).toList();
      final recoveredFiles = <File>[];
      for (final entity in entries.whereType<File>().where(
        (file) => file.path.endsWith('.bak'),
      )) {
        final original = File(entity.path.substring(0, entity.path.length - 4));
        if (!await original.exists()) {
          await entity.rename(original.path);
          recoveredFiles.add(original);
        }
      }
      for (final entity in [...entries, ...recoveredFiles]) {
        if (entity is! File ||
            !entity.uri.pathSegments.last.startsWith('community-sharing-') ||
            entity.path.endsWith('.tmp') ||
            entity.path.endsWith('.bak')) {
          continue;
        }
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map<String, dynamic> ||
              decoded['schema_version'] != 1 ||
              decoded['server_origin'] is! String) {
            continue;
          }
          final origin = decoded['server_origin'] as String;
          final rawReceipts = decoded['receipts'];
          if (rawReceipts is List) {
            for (final raw in rawReceipts.whereType<Map<String, dynamic>>()) {
              final receipt = CommunityReceipt.fromJson(raw);
              if (receipt.serverOrigin == origin &&
                  !receipts.any((old) => old.batchId == receipt.batchId)) {
                receipts.add(receipt);
              }
            }
          }
          final rawWithdrawn = decoded['withdrawn_event_ids'];
          if (rawWithdrawn is List) {
            withdrawnEventIds.addAll(rawWithdrawn.whereType<String>());
          }
          if (origin == serverOrigin) {
            sharingEnabled = decoded['sharing_enabled'] == true;
            final rawPending = decoded['pending'];
            if (rawPending is Map<String, dynamic>) {
              pending = CommunityPendingBatch.fromStorage(rawPending);
            }
          }
        } on Object {
          // One damaged endpoint file must not erase other service receipts.
        }
      }
    } on Object {
      // Corrupt private state must not block shortcut use or expose contents.
      if (serverOrigin == 'unconfigured') sharingEnabled = false;
    }
  }

  Set<String> get submittedEventIds => {
    for (final receipt in receipts) ...receipt.eventIds,
    ...withdrawnEventIds,
    if (pending != null) ...pending!.eventIds,
  };
  final Set<String> withdrawnEventIds = {};

  Future<void> setSharingEnabled(bool value) => _mutate(() {
    sharingEnabled = value;
  });

  Future<void> savePending(CommunityPendingBatch batch) => _mutate(() {
    if (batch.serverOrigin != serverOrigin || batch.cancelled) {
      throw ArgumentError('Pending batch belongs to a different service');
    }
    if (pending != null && pending!.batchId != batch.batchId) {
      throw StateError(
        'An unconfirmed batch must be resolved before creating another.',
      );
    }
    pending = batch;
  });

  Future<void> cancelPendingSubmission() {
    if (pending == null) return Future<void>.value();
    return _mutate(() {
      final batch = pending!;
      receipts.removeWhere((receipt) => receipt.batchId == batch.batchId);
      receipts.add(
        CommunityReceipt(
          batchId: batch.batchId,
          deleteToken: batch.deleteToken,
          eventIds: batch.eventIds,
          serverOrigin: batch.serverOrigin,
          mayBeAccepted: true,
        ),
      );
      pending = null;
    });
  }

  Future<void> acknowledgePending() => _mutate(() {
    final batch = pending;
    if (batch == null) return;
    receipts.removeWhere((receipt) => receipt.batchId == batch.batchId);
    receipts.add(
      CommunityReceipt(
        batchId: batch.batchId,
        deleteToken: batch.deleteToken,
        eventIds: batch.eventIds,
        serverOrigin: batch.serverOrigin,
      ),
    );
    pending = null;
  });

  Future<void> removeReceipt(String batchId) {
    var origin = serverOrigin;
    for (final receipt in receipts) {
      if (receipt.batchId == batchId) {
        origin = receipt.serverOrigin;
        break;
      }
    }
    return _mutate(() {
      for (final receipt in receipts.where(
        (receipt) => receipt.batchId == batchId,
      )) {
        withdrawnEventIds.addAll(receipt.eventIds);
      }
      receipts.removeWhere((receipt) => receipt.batchId == batchId);
    }, persistOrigin: origin);
  }

  Future<void> _mutate(void Function() action, {String? persistOrigin}) {
    final next = _writes.then((_) async {
      final beforeEnabled = sharingEnabled;
      final beforePending = pending;
      final beforeReceipts = [...receipts];
      final beforeWithdrawn = {...withdrawnEventIds};
      action();
      try {
        await _persist(origin: persistOrigin ?? serverOrigin);
      } catch (_) {
        sharingEnabled = beforeEnabled;
        pending = beforePending;
        receipts
          ..clear()
          ..addAll(beforeReceipts);
        withdrawnEventIds
          ..clear()
          ..addAll(beforeWithdrawn);
        rethrow;
      }
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _persist({required String origin}) async {
    await _directory.create(recursive: true);
    final file = _fileFor(origin);
    final dataMap = <String, dynamic>{};
    if (origin != serverOrigin && await file.exists()) {
      final previous = jsonDecode(await file.readAsString());
      if (previous is Map<String, dynamic>) dataMap.addAll(previous);
    }
    dataMap.addAll({
      'schema_version': 1,
      'server_origin': origin,
      if (origin == serverOrigin) 'sharing_enabled': sharingEnabled,
      if (origin == serverOrigin) 'pending': pending?.toStorage(),
      'receipts': [
        for (final receipt in receipts.where(
          (receipt) => receipt.serverOrigin == origin,
        ))
          receipt.toJson(),
      ],
      'withdrawn_event_ids': withdrawnEventIds.toList()..sort(),
    });
    final data = jsonEncode(dataMap);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(data, flush: true);
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }
}

class CommunityReceipt {
  const CommunityReceipt({
    required this.batchId,
    required this.deleteToken,
    required this.eventIds,
    required this.serverOrigin,
    this.mayBeAccepted = false,
  });

  final String batchId;
  final String deleteToken;
  final List<String> eventIds;
  final String serverOrigin;
  final bool mayBeAccepted;

  Map<String, Object> toJson() => {
    'batch_id': batchId,
    'delete_token': deleteToken,
    'event_ids': eventIds,
    'server_origin': serverOrigin,
    'may_be_accepted': mayBeAccepted,
  };

  factory CommunityReceipt.fromJson(Map<String, dynamic> json) =>
      CommunityReceipt(
        batchId: json['batch_id'] as String,
        deleteToken: json['delete_token'] as String,
        eventIds: (json['event_ids'] as List).cast<String>(),
        serverOrigin: json['server_origin'] as String,
        mayBeAccepted: json['may_be_accepted'] == true,
      );
}
