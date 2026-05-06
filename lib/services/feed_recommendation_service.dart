import 'dart:io';

import 'package:bling/services/content_embedding_service.dart';
import 'package:bling/services/feed_interaction_service.dart';
import 'package:vania/vania.dart';

class PostRecommendation {
  const PostRecommendation({
    required this.postId,
    required this.userId,
    required this.score,
  });

  final String postId;
  final String userId;
  final double score;
}

class FeedRecommendationService {
  FeedRecommendationService._();

  static final FeedRecommendationService instance =
      FeedRecommendationService._();

  final _embeddingService = ContentEmbeddingService.instance;
  final _interactionService = FeedInteractionService.instance;

  bool get isEnabled => true;
  bool get _logEnabled {
    final value = (Platform.environment['FEED_RECOMMENDATION_LOGS'] ??
            env('FEED_RECOMMENDATION_LOGS', '') ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return value == '1' || value == 'true' || value == 'yes' || value == 'on';
  }

  Future<void> backfillRecentPosts({int limit = 250}) async {
    if (!isEnabled) return;
    try {
      final rows = await connection!.select(
        '''
        SELECT id, user_id, caption, post_type, hashtags::TEXT AS hashtags, media_kind, is_active, created_at
        FROM posts
        WHERE is_active = 1
        ORDER BY created_at DESC
        LIMIT \$1
        ''',
        [limit],
      );

      for (final row in rows) {
        await _upsertPostEmbedding(row);
      }
    } catch (error) {
      _logSoftFailure('backfillRecentPosts', error);
    }
  }

  Future<void> indexPost(Map<String, dynamic> row) async {
    if (!isEnabled) return;
    try {
      await _upsertPostEmbedding(row);
    } catch (error) {
      _logSoftFailure('indexPost', error);
    }
  }

  Future<void> deletePost(String postId) async {
    if (!isEnabled || postId.trim().isEmpty || !_isUuid(postId)) return;
    try {
      await connection!.statement(
        'DELETE FROM post_embeddings WHERE post_id = \$1::uuid',
        [postId.trim()],
      );
    } catch (error) {
      _logSoftFailure('deletePost', error);
    }
  }

  Future<List<String>> recommendPostIds({
    required String authUserId,
    required List<String> blockedUserIds,
    required int limit,
  }) async {
    if (!isEnabled || authUserId.trim().isEmpty || limit <= 0) return const [];
    try {
      await backfillRecentPosts();

      final positiveIds = await _loadPositivePostIds(authUserId);
      if (positiveIds.isEmpty) {
        _log(
          'recommendPostIds:no_seeds auth_user_id=$authUserId limit=$limit',
        );
        return const [];
      }

      final candidates = await _recommendByPostIds(
        positivePostIds: positiveIds,
        authUserId: authUserId,
        blockedUserIds: blockedUserIds,
        limit: limit * 4,
      );

      final seen = <String>{...positiveIds};
      final perUserCount = <String, int>{};
      final results = <String>[];

      for (final candidate in candidates) {
        if (candidate.postId.isEmpty) continue;
        if (seen.contains(candidate.postId)) continue;
        if (blockedUserIds.contains(candidate.userId)) continue;

        final userCount = perUserCount[candidate.userId] ?? 0;
        if (candidate.userId.isNotEmpty && userCount >= 2) continue;

        seen.add(candidate.postId);
        if (candidate.userId.isNotEmpty) {
          perUserCount[candidate.userId] = userCount + 1;
        }
        results.add(candidate.postId);
        if (results.length >= limit) break;
      }

      _log(
        'recommendPostIds:ok auth_user_id=$authUserId seeds=${positiveIds.length} candidates=${candidates.length} results=${results.length} blocked=${blockedUserIds.length} limit=$limit',
      );
      return results;
    } catch (error) {
      _logSoftFailure('recommendPostIds', error);
      return const [];
    }
  }

  Future<List<String>> _loadPositivePostIds(String authUserId) async {
    final interactionIds = await _interactionService.loadPositivePostIds(
      authUserId,
      limit: 12,
    );
    if (interactionIds.isNotEmpty) return interactionIds;

    final followedRows = await connection!.select(
      '''
      SELECT p.id
      FROM follows f
      INNER JOIN posts p ON TRIM(p.user_id) = TRIM(f.following_id)
      WHERE TRIM(f.follower_id) = TRIM(\$1)
        AND p.is_active = 1
      ORDER BY p.created_at DESC
      LIMIT 12
      ''',
      [authUserId],
    );
    final followedIds = followedRows
        .map((row) => row['id']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
    if (followedIds.isNotEmpty) return followedIds;

    final ownRows = await connection!.select(
      '''
      SELECT id
      FROM posts
      WHERE TRIM(user_id) = TRIM(\$1) AND is_active = 1
      ORDER BY created_at DESC
      LIMIT 8
      ''',
      [authUserId],
    );
    return ownRows
        .map((row) => row['id']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _upsertPostEmbedding(Map<String, dynamic> row) async {
    final postId = row['id']?.toString() ?? '';
    final userId = row['user_id']?.toString() ?? '';
    if (!_isUuid(postId) || !_isUuid(userId)) return;

    final caption = row['caption']?.toString() ?? '';
    final postType = row['post_type']?.toString() ?? 'feed';
    final mediaKind = row['media_kind']?.toString() ?? 'image';
    final hashtags = _embeddingService.parseHashtags(row['hashtags']);
    final vector = _embeddingService.embedPost(
      caption: caption,
      postType: postType,
      hashtags: hashtags,
      mediaKind: mediaKind,
    );
    final now = DateTime.now().toIso8601String();
    final createdAt = row['created_at']?.toString() ?? now;

    await connection!.statement(
      '''
      INSERT INTO post_embeddings (
        post_id, user_id, embedding, created_at, updated_at
      )
      VALUES (\$1::uuid, \$2::uuid, \$3::vector, \$4, \$5)
      ON CONFLICT (post_id)
      DO UPDATE SET
        user_id = EXCLUDED.user_id,
        embedding = EXCLUDED.embedding,
        updated_at = EXCLUDED.updated_at
      ''',
      [postId, userId, _toVectorLiteral(vector), createdAt, now],
    );
  }

  Future<List<PostRecommendation>> _recommendByPostIds({
    required List<String> positivePostIds,
    required String authUserId,
    required List<String> blockedUserIds,
    required int limit,
  }) async {
    final validPositiveIds = positivePostIds.where(_isUuid).toList();
    if (validPositiveIds.isEmpty || !_isUuid(authUserId) || limit <= 0) {
      return const [];
    }

    final positiveClause = _uuidListClause(validPositiveIds);
    final blockedTextClause = _textListClause(
      blockedUserIds.map((item) => item.trim()).where((item) => item.isNotEmpty),
    );

    final rows = await connection!.select(
      '''
      WITH seed_posts AS (
        SELECT embedding
        FROM post_embeddings
        WHERE post_id IN ($positiveClause)
      ),
      seed_vector AS (
        SELECT AVG(embedding) AS embedding
        FROM seed_posts
      )
      SELECT pe.post_id, pe.user_id, 1 - (pe.embedding <=> sv.embedding) AS score
      FROM post_embeddings pe
      CROSS JOIN seed_vector sv
      INNER JOIN posts p ON TRIM(p.id) = TRIM(pe.post_id::text)
      WHERE sv.embedding IS NOT NULL
        AND p.is_active = 1
        AND TRIM(pe.user_id::text) <> TRIM('$authUserId')
        AND pe.post_id NOT IN ($positiveClause)
        ${blockedTextClause.isEmpty ? '' : 'AND TRIM(pe.user_id::text) NOT IN ($blockedTextClause)'}
      ORDER BY pe.embedding <=> sv.embedding ASC, p.created_at DESC
      LIMIT $limit
      ''',
      [],
    );

    return rows
        .map(
          (row) => PostRecommendation(
            postId: row['post_id']?.toString() ?? '',
            userId: row['user_id']?.toString() ?? '',
            score: (row['score'] as num?)?.toDouble() ?? 0,
          ),
        )
        .where((item) => item.postId.isNotEmpty)
        .toList();
  }

  void _logSoftFailure(String operation, Object error) {
    print('FeedRecommendationService.$operation soft failure: $error');
  }

  void _log(String message) {
    if (!_logEnabled) return;
    print('[FeedRec] $message');
  }

  bool _isUuid(String value) {
    final normalized = value.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(normalized);
  }

  String _toVectorLiteral(List<double> values) {
    return '[${values.map((value) => value.toStringAsFixed(8)).join(',')}]';
  }

  String _uuidListClause(Iterable<String> values) {
    final items = values
        .map((value) => value.trim())
        .where(_isUuid)
        .map((value) => "'$value'::uuid")
        .toList();
    return items.join(', ');
  }

  String _textListClause(Iterable<String> values) {
    final items = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => "'$value'")
        .toList();
    return items.join(', ');
  }
}
