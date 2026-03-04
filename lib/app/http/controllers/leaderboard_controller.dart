import 'dart:io';

import 'package:vania/vania.dart';

class LeaderboardController extends Controller {
  /// GET /api/leaderboard?period=global|daily|weekly&page=&limit=
  Future<Response> getLeaderboard(Request request) async {
    final period = request.input('period') as String? ?? 'global';
    final page =
        int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '50') ?? 50;
    final authUserId = request.input('auth_user_id') as String? ?? '';

    try {
      String dateFilter = '';
      if (period == 'daily') {
        dateFilter = "AND posts.created_at >= NOW() - INTERVAL '1 day'";
      } else if (period == 'weekly') {
        dateFilter = "AND posts.created_at >= NOW() - INTERVAL '7 days'";
      }

      // For global leaderboard, use bling_score on user
      // For time-based, calculate from post likes + challenge entries
      List<Map<String, dynamic>> leaders;

      if (period == 'global') {
        leaders = await connection!.select(
          '''SELECT u.id, u.name, u.username, u.avatar, u.is_verified,
             u.bling_score as score,
             w.balance as bling_balance,
             ROW_NUMBER() OVER (ORDER BY u.bling_score DESC) as rank
             FROM users u
             LEFT JOIN wallets w ON w.user_id = u.id
             WHERE u.deleted_at IS NULL
             ORDER BY u.bling_score DESC
             LIMIT \$1 OFFSET \$2''',
          [limit, (page - 1) * limit],
        );
      } else {
        // Time-based: score = likes received + challenge entries * 5
        leaders = await connection!.select(
          '''SELECT u.id, u.name, u.username, u.avatar, u.is_verified,
             COALESCE(SUM(DISTINCT post_likes.like_count), 0) +
             COALESCE(COUNT(DISTINCT ce.id) * 5, 0) as score,
             ROW_NUMBER() OVER (ORDER BY (COALESCE(SUM(DISTINCT post_likes.like_count), 0) + COALESCE(COUNT(DISTINCT ce.id) * 5, 0)) DESC) as rank
             FROM users u
             LEFT JOIN posts p ON p.user_id = u.id $dateFilter
             LEFT JOIN (
               SELECT post_id, COUNT(*) as like_count
               FROM likes
               GROUP BY post_id
             ) post_likes ON post_likes.post_id = p.id
             LEFT JOIN challenge_entries ce ON ce.user_id = u.id
             WHERE u.deleted_at IS NULL
             GROUP BY u.id, u.name, u.username, u.avatar, u.is_verified
             ORDER BY score DESC
             LIMIT \$1 OFFSET \$2''',
          [limit, (page - 1) * limit],
        );
      }

      // Find auth user's rank
      int? myRank;
      if (authUserId.isNotEmpty) {
        final idx = leaders.indexWhere((l) => l['id'] == authUserId);
        if (idx >= 0) {
          myRank = (leaders[idx]['rank'] as num?)?.toInt();
        }
      }

      return Response.json({
        'leaderboard': {
          'period': period,
          'page': page,
          'my_rank': myRank,
          'data': leaders.map((l) => {
                'rank': (l['rank'] as num?)?.toInt(),
                'id': l['id'],
                'name': l['name'],
                'username': l['username'],
                'avatar': l['avatar'],
                'is_verified': l['is_verified'],
                'score': (l['score'] as num?)?.toInt() ?? 0,
                'bling_balance': (l['bling_balance'] as num?)?.toInt() ?? 0,
                'is_me': l['id'] == authUserId,
              }).toList(),
        }
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching leaderboard',
        'error': e.toString(),
      }, 500);
    }
  }
}

final LeaderboardController leaderboardController = LeaderboardController();
