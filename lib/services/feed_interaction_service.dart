import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class FeedInteractionService {
  FeedInteractionService._();

  static final FeedInteractionService instance = FeedInteractionService._();

  Future<void> record({
    required String userId,
    required String postId,
    required String interactionType,
    String source = 'feed',
    int dwellMs = 0,
    Map<String, dynamic>? metadata,
  }) async {
    if (userId.trim().isEmpty || postId.trim().isEmpty) return;

    final now = DateTime.now().toIso8601String();
    await connection!.statement(
      '''
      INSERT INTO feed_interactions (
        id, user_id, post_id, interaction_type, source, dwell_ms, metadata, created_at, updated_at
      )
      VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)
      ''',
      [
        const Uuid().v4(),
        userId.trim(),
        postId.trim(),
        interactionType.trim().toLowerCase(),
        source.trim().isEmpty ? 'feed' : source.trim().toLowerCase(),
        dwellMs < 0 ? 0 : dwellMs,
        jsonEncode(metadata ?? const <String, dynamic>{}),
        now,
        now,
      ],
    );
  }

  Future<List<String>> loadPositivePostIds(
    String userId, {
    int limit = 16,
  }) async {
    if (userId.trim().isEmpty) return const [];

    final rows = await connection!.select(
      '''
      SELECT post_id,
             SUM(
               CASE interaction_type
                 WHEN 'repost' THEN 7
                 WHEN 'comment' THEN 5
                 WHEN 'like' THEN 4
                 WHEN 'open' THEN 3
                 WHEN 'dwell' THEN CASE WHEN dwell_ms >= 8000 THEN 4 ELSE 2 END
                 WHEN 'impression' THEN 1
                 ELSE 1
               END
             ) AS score,
             MAX(created_at) AS last_seen
      FROM feed_interactions
      WHERE user_id = \$1
      GROUP BY post_id
      ORDER BY score DESC, last_seen DESC
      LIMIT \$2
      ''',
      [userId.trim(), limit],
    );

    return rows
        .map((row) => row['post_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }
}
