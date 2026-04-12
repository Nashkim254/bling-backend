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

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_apiKey.trim().isNotEmpty) 'api-key': _apiKey.trim(),
      };

  Future<void> ensureCollection() async {
    if (!isEnabled || _collectionReady) return;

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

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _collectionReady = true;
      return;
    }

    throw HttpException(
      'Failed to ensure Qdrant collection: ${response.statusCode} ${response.body}',
    );
  }

  Future<void> upsertPosts(List<Map<String, dynamic>> points) async {
    if (!isEnabled || points.isEmpty) return;
    await ensureCollection();

    final response = await http.put(
      Uri.parse('$_baseUrl/collections/$_collection/points?wait=true'),
      headers: _headers,
      body: jsonEncode({'points': points}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Failed to upsert Qdrant points: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> deletePosts(List<String> postIds) async {
    if (!isEnabled || postIds.isEmpty) return;
    await ensureCollection();

    final response = await http.post(
      Uri.parse('$_baseUrl/collections/$_collection/points/delete?wait=true'),
      headers: _headers,
      body: jsonEncode({
        'points': postIds,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Failed to delete Qdrant points: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<List<QdrantRecommendation>> recommendByPostIds({
    required List<String> positivePostIds,
    required int limit,
  }) async {
    if (!isEnabled || positivePostIds.isEmpty || limit <= 0) return const [];
    await ensureCollection();

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
      throw HttpException(
        'Failed to recommend Qdrant points: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final items = (decoded['result'] as List? ?? []).whereType<Map>();
    return items
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
  }

  Future<bool> isReachable() async {
    if (!isEnabled) return false;

    try {
      final response = await http.get(
        Uri.parse(_baseUrl),
        headers: _headers,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
