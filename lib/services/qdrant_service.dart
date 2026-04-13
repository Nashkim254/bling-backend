import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vania/vania.dart';

class QdrantRecommendation {
  const QdrantRecommendation({
    required this.postId,
    required this.userId,
    required this.score,
  });

  final String postId;
  final String userId;
  final double score;
}

class QdrantService {
  QdrantService._();

  static final QdrantService instance = QdrantService._();

  bool _collectionReady = false;

  String get _baseUrl =>
      Platform.environment['QDRANT_URL'] ?? env('QDRANT_URL', '');
  String get _apiKey => Platform.environment['QDRANT_API_KEY'] ??
      env('QDRANT_API_KEY', '');
  String get _collection => Platform.environment['QDRANT_POSTS_COLLECTION'] ??
      env('QDRANT_POSTS_COLLECTION', 'feed_posts');
  int get _vectorSize => int.tryParse(
        Platform.environment['QDRANT_VECTOR_SIZE'] ??
            env('QDRANT_VECTOR_SIZE', '256'),
      ) ??
      256;

  bool get isEnabled => _baseUrl.trim().isNotEmpty;
  bool get _logEnabled {
    final value =
        (Platform.environment['QDRANT_LOGS'] ?? env('QDRANT_LOGS', '') ?? '')
            .toString();
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  Uri? get _baseUri => Uri.tryParse(_baseUrl);
  String get _safeBase =>
      '${_baseUri?.scheme ?? 'unknown'}://${_baseUri?.host ?? _baseUrl}${_baseUri?.hasPort == true ? ':${_baseUri!.port}' : ''}';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_apiKey.trim().isNotEmpty) 'api-key': _apiKey.trim(),
      };

  Future<void> ensureCollection() async {
    if (!isEnabled || _collectionReady) return;
    final startedAt = DateTime.now();
    _log('ensureCollection:start collection=$_collection vector_size=$_vectorSize');

    final response = await http.put(
      Uri.parse('$_baseUrl/collections/$_collection'),
      headers: _headers,
      body: jsonEncode({
        'vectors': {
          'size': _vectorSize,
          'distance': 'Cosine',
        },
      }),
    );

    final responseBody = response.body.toLowerCase();
    final alreadyExists = response.statusCode == 409 &&
        responseBody.contains('already exists');

    if ((response.statusCode >= 200 && response.statusCode < 300) ||
        alreadyExists) {
      _collectionReady = true;
      _log(
        'ensureCollection:ok status=${response.statusCode} already_exists=$alreadyExists duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
      return;
    }

    _log(
      'ensureCollection:error status=${response.statusCode} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
    );

    throw HttpException(
      'Failed to ensure Qdrant collection: ${response.statusCode} ${response.body}',
    );
  }

  Future<void> upsertPosts(List<Map<String, dynamic>> points) async {
    if (!isEnabled || points.isEmpty) return;
    await ensureCollection();
    final startedAt = DateTime.now();
    _log('upsertPosts:start collection=$_collection points=${points.length}');

    final response = await http.put(
      Uri.parse('$_baseUrl/collections/$_collection/points?wait=true'),
      headers: _headers,
      body: jsonEncode({'points': points}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log(
        'upsertPosts:error status=${response.statusCode} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
      throw HttpException(
        'Failed to upsert Qdrant points: ${response.statusCode} ${response.body}',
      );
    }

    _log(
      'upsertPosts:ok status=${response.statusCode} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
    );
  }

  Future<void> deletePosts(List<String> postIds) async {
    if (!isEnabled || postIds.isEmpty) return;
    await ensureCollection();
    final startedAt = DateTime.now();
    _log('deletePosts:start collection=$_collection points=${postIds.length}');

    final response = await http.post(
      Uri.parse('$_baseUrl/collections/$_collection/points/delete?wait=true'),
      headers: _headers,
      body: jsonEncode({
        'points': postIds,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log(
        'deletePosts:error status=${response.statusCode} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
      throw HttpException(
        'Failed to delete Qdrant points: ${response.statusCode} ${response.body}',
      );
    }

    _log(
      'deletePosts:ok status=${response.statusCode} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
    );
  }

  Future<List<QdrantRecommendation>> recommendByPostIds({
    required List<String> positivePostIds,
    required int limit,
  }) async {
    if (!isEnabled || positivePostIds.isEmpty || limit <= 0) return const [];
    await ensureCollection();
    final startedAt = DateTime.now();
    _log(
      'recommendByPostIds:start collection=$_collection positives=${positivePostIds.length} limit=$limit',
    );

    final response = await http.post(
      Uri.parse('$_baseUrl/collections/$_collection/points/recommend'),
      headers: _headers,
      body: jsonEncode({
        'positive': positivePostIds,
        'limit': limit,
        'with_payload': ['post_id', 'user_id'],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log(
        'recommendByPostIds:error status=${response.statusCode} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
      throw HttpException(
        'Failed to recommend Qdrant points: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final items = (decoded['result'] as List? ?? []).whereType<Map>();
    final results = items
        .map((item) {
          final payload =
              (item['payload'] as Map?)?.cast<String, dynamic>() ?? {};
          return QdrantRecommendation(
            postId:
                payload['post_id']?.toString() ?? item['id']?.toString() ?? '',
            userId: payload['user_id']?.toString() ?? '',
            score: (item['score'] as num?)?.toDouble() ?? 0,
          );
        })
        .where((item) => item.postId.isNotEmpty)
        .toList();

    _log(
      'recommendByPostIds:ok status=${response.statusCode} results=${results.length} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
    );
    return results;
  }

  Future<bool> isReachable() async {
    if (!isEnabled) return false;
    final startedAt = DateTime.now();

    try {
      final response = await http.get(
        Uri.parse(_baseUrl),
        headers: _headers,
      );
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      _log(
        'isReachable:${ok ? 'ok' : 'error'} status=${response.statusCode} duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
      return ok;
    } catch (_) {
      _log(
        'isReachable:error duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
      return false;
    }
  }

  void _log(String message) {
    if (!_logEnabled) return;
    print('[Qdrant] base=$_safeBase $message');
  }
}
