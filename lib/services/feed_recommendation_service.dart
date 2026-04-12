import 'dart:convert';

import 'package:bling/services/content_embedding_service.dart';
import 'package:bling/services/feed_interaction_service.dart';
import 'package:bling/services/qdrant_service.dart';
import 'package:vania/vania.dart';

class FeedRecommendationService {
  FeedRecommendationService._();

  static final FeedRecommendationService instance =
      FeedRecommendationService._();

  final _embeddingService = ContentEmbeddingService.instance;
  final _interactionService = FeedInteractionService.instance;
  final _qdrantService = QdrantService.instance;

  bool get isEnabled => _qdrantService.isEnabled;

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

      final points = rows.map(_postRowToPoint).toList();
      await _qdrantService.upsertPosts(points);
    } catch (error) {
      _logSoftFailure('backfillRecentPosts', error);
    }
  }

  Future<void> indexPost(Map<String, dynamic> row) async {
    if (!isEnabled) return;
    try {
      await _qdrantService.upsertPosts([_postRowToPoint(row)]);
    } catch (error) {
      _logSoftFailure('indexPost', error);
    }
  }

  Future<void> deletePost(String postId) async {
    if (!isEnabled || postId.trim().isEmpty) return;
    try {
      await _qdrantService.deletePosts([postId.trim()]);
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
      if (positiveIds.isEmpty) return const [];

      final candidates = await _qdrantService.recommendByPostIds(
        positivePostIds: positiveIds,
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
      INNER JOIN posts p ON p.user_id = f.following_id
      WHERE f.follower_id = \$1
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
      WHERE user_id = \$1 AND is_active = 1
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

  Map<String, dynamic> _postRowToPoint(Map<String, dynamic> row) {
    final postId = row['id']?.toString() ?? '';
    final userId = row['user_id']?.toString() ?? '';
    final caption = row['caption']?.toString() ?? '';
    final postType = row['post_type']?.toString() ?? 'feed';
    final mediaKind = row['media_kind']?.toString() ?? 'image';
    final hashtags = _embeddingService.parseHashtags(row['hashtags']);
    final createdAtText = row['created_at']?.toString() ?? '';
    final createdAt = DateTime.tryParse(createdAtText);
    final vector = _embeddingService.embedPost(
      caption: caption,
      postType: postType,
      hashtags: hashtags,
      mediaKind: mediaKind,
    );

    return {
      'id': postId,
      'vector': vector,
      'payload': {
        'post_id': postId,
        'user_id': userId,
        'caption': caption,
        'post_type': postType,
        'media_kind': mediaKind,
        'hashtags': hashtags,
        'is_active': (row['is_active'] as num?)?.toInt() == 1,
        'created_at': createdAtText,
        'created_at_ts': createdAt?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        'document': jsonEncode({
          'caption': caption,
          'post_type': postType,
          'media_kind': mediaKind,
          'hashtags': hashtags,
        }),
      },
    };
  }

  void _logSoftFailure(String operation, Object error) {
    print('FeedRecommendationService.$operation soft failure: $error');
  }
}
