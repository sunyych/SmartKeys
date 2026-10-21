import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Safe aggregate category shown in the public rankings.
class CommunityRankingRow {
  const CommunityRankingRow({
    required this.shortcutId,
    required this.count,
    required this.contributions,
  });

  final String shortcutId;
  final int count;
  final int contributions;
}

class CommunityRanking {
  const CommunityRanking({
    required this.period,
    required this.tag,
    required this.updatedAt,
    required this.rows,
  });

  final String period;
  final String? tag;
  final DateTime updatedAt;
  final List<CommunityRankingRow> rows;
}

/// Minimal HTTP client for the v1 public aggregate API.
class ShortcutCommunityClient {
  ShortcutCommunityClient({
    String endpoint = const String.fromEnvironment('SMARTKEYS_RANKING_URL'),
    HttpClient Function()? clientFactory,
    bool allowLoopbackHttp = false,
    this.timeout = const Duration(seconds: 8),
    this.maxResponseBytes = 32768,
  }) : _endpoint = _validateEndpoint(endpoint, allowLoopbackHttp),
       _clientFactory = clientFactory ?? HttpClient.new;

  final Uri? _endpoint;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  final int maxResponseBytes;

  bool get isConfigured => _endpoint != null;
  String? get serverOrigin => _endpoint?.toString();

  static Uri? _validateEndpoint(String raw, bool allowLoopbackHttp) {
    if (raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError('Invalid ranking service endpoint');
    }
    final loopback =
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1' ||
        uri.host == '[::1]';
    if (uri.scheme != 'https' &&
        !(allowLoopbackHttp && loopback && uri.scheme == 'http')) {
      throw ArgumentError('Ranking service endpoint must use HTTPS');
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
  }

  Uri? _uri(String path, [Map<String, String>? query]) => _endpoint?.replace(
    path: '${_endpoint.path}$path',
    queryParameters: query,
  );

  Future<CommunityRanking> fetchRankings(String period, {String? tag}) async {
    if (!const {'all', '7d', '30d'}.contains(period)) {
      throw ArgumentError.value(period, 'period');
    }
    if (tag != null && !communityProfessionTags.containsKey(tag)) {
      throw ArgumentError.value(tag, 'tag');
    }
    final query = {'period': period};
    if (tag != null) query['tag'] = tag;
    final uri = _uri('/v1/rankings', query);
    if (uri == null) throw const CommunityServiceException('not_configured');
    final result = await _request('GET', uri);
    if (result.statusCode != 200) throw _statusError(result.statusCode);
    try {
      final json = jsonDecode(utf8.decode(result.body));
      if (json is! Map<String, dynamic> ||
          json['schema_version'] != 1 ||
          json['period'] != period ||
          !json.containsKey('tag') ||
          json['tag'] != tag ||
          json['rankings'] is! List ||
          json['updated_at'] is! String) {
        throw const FormatException();
      }
      final rows = <CommunityRankingRow>[];
      for (final raw in json['rankings'] as List) {
        if (raw is! Map<String, dynamic>) throw const FormatException();
        final id = raw['shortcut_id'];
        final count = raw['count'];
        final contributions = raw['contributions'];
        if (id is! String ||
            !communityShortcutIds.contains(id) ||
            count is! int ||
            count < 0 ||
            contributions is! int ||
            contributions < 0) {
          throw const FormatException();
        }
        rows.add(
          CommunityRankingRow(
            shortcutId: id,
            count: count,
            contributions: contributions,
          ),
        );
      }
      return CommunityRanking(
        period: period,
        tag: tag,
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
        rows: List.unmodifiable(rows),
      );
    } on FormatException {
      throw const CommunityServiceException('invalid_response');
    } on TypeError {
      throw const CommunityServiceException('invalid_response');
    }
  }

  Future<void> submit(CommunityPendingBatch batch) async {
    if (batch.serverOrigin != serverOrigin || batch.cancelled) {
      throw const CommunityServiceException('wrong_origin');
    }
    final uri = _uri('/v1/contributions');
    if (uri == null) throw const CommunityServiceException('not_configured');
    final bytes = utf8.encode(jsonEncode(batch.toPayload()));
    if (bytes.length > 16384) {
      throw const CommunityServiceException('invalid_batch');
    }
    final result = await _request('POST', uri, body: bytes);
    if (result.statusCode != 200 && result.statusCode != 201) {
      throw _statusError(result.statusCode);
    }
    try {
      final json = jsonDecode(utf8.decode(result.body));
      if (json is! Map<String, dynamic> ||
          json['schema_version'] != 1 ||
          json['batch_id'] != batch.batchId ||
          json['status'] != 'accepted') {
        throw const FormatException();
      }
    } on FormatException {
      throw const CommunityServiceException('invalid_response');
    }
  }

  Future<void> withdraw(
    String batchId,
    String deleteToken, {
    String? origin,
  }) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(batchId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(deleteToken)) {
      throw const CommunityServiceException('invalid_receipt');
    }
    final uri = _uri('/v1/contributions/$batchId');
    if (uri == null) throw const CommunityServiceException('not_configured');
    if (origin != null && origin != serverOrigin) {
      throw const CommunityServiceException('wrong_origin');
    }
    final result = await _request(
      'DELETE',
      uri,
      headers: {'authorization': 'Bearer $deleteToken'},
    );
    if (result.statusCode != 204) throw _statusError(result.statusCode);
  }

  Future<_HttpResult> _request(
    String method,
    Uri uri, {
    List<int>? body,
    Map<String, String>? headers,
  }) async {
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(body);
      }
      headers?.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const CommunityServiceException('response_too_large');
        }
        bytes.addAll(chunk);
      }
      if (response.isRedirect) {
        throw const CommunityServiceException('redirect_rejected');
      }
      return _HttpResult(response.statusCode, bytes);
    } on TimeoutException {
      throw const CommunityServiceException('timeout');
    } on SocketException {
      throw const CommunityServiceException('unavailable');
    } on HttpException {
      throw const CommunityServiceException('unavailable');
    } finally {
      client.close(force: true);
    }
  }

  CommunityServiceException _statusError(int status) =>
      CommunityServiceException(switch (status) {
        409 => 'conflict',
        410 => 'withdrawn',
        429 => 'rate_limited',
        300 || 301 || 302 || 303 || 307 || 308 => 'redirect_rejected',
        _ => 'request_failed',
      });
}

const communityShortcutIds = <String>{
  'copy',
  'paste',
  'cut',
  'undo',
  'redo',
  'select_all',
  'save',
  'find',
  'new',
  'open',
  'print',
  'new_tab',
  'close_tab',
  'bold',
  'italic',
};

const communityProfessionTags = <String, String>{
  'software_engineering': 'Software engineering',
  'design': 'Design',
  'video_editing': 'Video editing',
  'office': 'Office work',
  'other': 'Other',
};

class CommunityPendingBatch {
  CommunityPendingBatch({
    required this.batchId,
    required this.deleteToken,
    required this.serverOrigin,
    required Map<String, int> items,
    required this.eventIds,
    this.tag,
    this.cancelled = false,
  }) : items = Map.unmodifiable(items) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(batchId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(deleteToken) ||
        items.isEmpty ||
        items.length > 15 ||
        (tag != null && !communityProfessionTags.containsKey(tag)) ||
        items.entries.any(
          (e) => !communityShortcutIds.contains(e.key) || e.value <= 0,
        ) ||
        items.values.fold<int>(0, (a, b) => a + b) > 100000) {
      throw ArgumentError('Invalid community batch');
    }
  }

  final String batchId;
  final String deleteToken;
  final String serverOrigin;
  final Map<String, int> items;

  /// Local-only acknowledgement mapping; never included in [toPayload].
  final List<String> eventIds;
  final String? tag;
  final bool cancelled;

  Map<String, Object?> toPayload() => {
    'schema_version': 1,
    'batch_id': batchId,
    'delete_token': deleteToken,
    'tag': tag,
    'items': [
      for (final id in items.keys.toList()..sort())
        {'shortcut_id': id, 'count': items[id]},
    ],
  };

  Map<String, Object?> toStorage() => {
    ...toPayload(),
    'event_ids': eventIds,
    'server_origin': serverOrigin,
    'cancelled': cancelled,
  };

  factory CommunityPendingBatch.fromStorage(Map<String, dynamic> json) =>
      CommunityPendingBatch(
        batchId: json['batch_id'] as String,
        deleteToken: json['delete_token'] as String,
        serverOrigin: json['server_origin'] as String,
        tag: json['tag'] as String?,
        cancelled: json['cancelled'] == true,
        items: {
          for (final item in json['items'] as List)
            (item as Map<String, dynamic>)['shortcut_id'] as String:
                item['count'] as int,
        },
        eventIds: (json['event_ids'] as List).cast<String>(),
      );
}

class CommunityServiceException implements Exception {
  const CommunityServiceException(this.code);
  final String code;
  @override
  String toString() => 'Community service error: $code';
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body);
  final int statusCode;
  final List<int> body;
}
