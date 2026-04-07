import 'dart:io';

import 'package:vania/vania.dart';

class LeaderboardController extends Controller {
  String _authUserId(Request request) {
    final requestUserId = request.input('auth_user_id')?.toString() ?? '';
    if (requestUserId.isNotEmpty) return requestUserId;
    return Auth().id()?.toString() ?? '';
  }

  /// GET /api/leaderboard?period=global|daily|weekly|monthly
  ///   &sort_by=score|balance
  ///   &following_only=true
  ///   &verified_only=true
  ///   &page=&limit=
  Future<Response> getLeaderboard(Request request) async {
    final period = request.input('period')?.toString() ?? 'global';
    final sortBy = request.input('sort_by')?.toString() ?? 'score';
    final followingOnly = request.input('following_only')?.toString() == 'true';
    final verifiedOnly = request.input('verified_only')?.toString() == 'true';
    final search = request.input('search')?.toString().trim() ?? '';
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '50') ?? 50;
    final authUserId = _authUserId(request);

    try {
      // Period date filter
      String dateFilter = '';
      if (period == 'daily') {
        dateFilter = "AND p.created_at >= NOW() - INTERVAL '1 day'";
      } else if (period == 'weekly') {
        dateFilter = "AND p.created_at >= NOW() - INTERVAL '7 days'";
      } else if (period == 'monthly') {
        dateFilter = "AND p.created_at >= NOW() - INTERVAL '30 days'";
      }

      // Verified filter
      final verifiedClause = verifiedOnly ? 'AND u.is_verified = true' : '';

      // Search filter
      final searchClause = search.isNotEmpty
          ? "AND (LOWER(u.name) LIKE LOWER('%$search%') OR LOWER(u.username) LIKE LOWER('%$search%'))"
          : '';

      // Following filter — only applies when auth user is known
      final followingJoin = followingOnly && authUserId.isNotEmpty
          ? "INNER JOIN follows f ON f.following_id = u.id AND f.follower_id = '$authUserId'"
          : '';

      // Sort column
      final sortColumn = sortBy == 'balance' ? 'w.balance' : 'u.bling_score';
      final scoreAlias = sortBy == 'balance' ? 'w.balance' : 'u.bling_score';

      List<Map<String, dynamic>> leaders;

      if (period == 'global') {
        leaders = await connection!.select(
          '''SELECT u.id, u.name, u.username, u.avatar, u.is_verified,
             $scoreAlias as score,
             w.balance as bling_balance,
             ROW_NUMBER() OVER (ORDER BY $sortColumn DESC NULLS LAST) as rank
             FROM users u
             LEFT JOIN wallets w ON w.user_id = u.id
             $followingJoin
             WHERE u.deleted_at IS NULL $verifiedClause $searchClause
             ORDER BY $sortColumn DESC NULLS LAST
             LIMIT \$1 OFFSET \$2''',
          [limit, (page - 1) * limit],
        );
      } else {
        // Time-based: score = likes received + challenge entries * 5
        leaders = await connection!.select(
          '''SELECT u.id, u.name, u.username, u.avatar, u.is_verified,
             COALESCE(SUM(DISTINCT post_likes.like_count), 0) +
             COALESCE(COUNT(DISTINCT ce.id) * 5, 0) as score,
             w.balance as bling_balance,
             ROW_NUMBER() OVER (ORDER BY (COALESCE(SUM(DISTINCT post_likes.like_count), 0) + COALESCE(COUNT(DISTINCT ce.id) * 5, 0)) DESC) as rank
             FROM users u
             LEFT JOIN wallets w ON w.user_id = u.id
             LEFT JOIN posts p ON p.user_id = u.id $dateFilter
             LEFT JOIN (
               SELECT post_id, COUNT(*) as like_count
               FROM likes
               GROUP BY post_id
             ) post_likes ON post_likes.post_id = p.id
             LEFT JOIN challenge_entries ce ON ce.user_id = u.id
             $followingJoin
             WHERE u.deleted_at IS NULL $verifiedClause $searchClause
             GROUP BY u.id, u.name, u.username, u.avatar, u.is_verified, w.balance
             ORDER BY score DESC
             LIMIT \$1 OFFSET \$2''',
          [limit, (page - 1) * limit],
        );
      }

      // Find auth user's rank
      int? myRank;
      final leaderRows = leaders.whereType<Map<String, dynamic>>().toList();

      if (authUserId.isNotEmpty) {
        final idx = leaderRows.indexWhere((l) => l['id'] == authUserId);
        if (idx >= 0) {
          myRank = (leaderRows[idx]['rank'] as num?)?.toInt();
        }
      }

      return Response.json({
        'leaderboard': {
          'period': period,
          'sort_by': sortBy,
          'page': page,
          'my_rank': myRank,
          'data': leaderRows
              .map((l) => {
                    'rank': (l['rank'] as num?)?.toInt(),
                    'id': l['id'],
                    'name': l['name'],
                    'username': l['username'],
                    'avatar': l['avatar'],
                    'is_verified': l['is_verified'],
                    'score': (l['score'] as num?)?.toInt() ?? 0,
                    'bling_balance': (l['bling_balance'] as num?)?.toInt() ?? 0,
                    'is_me': l['id'] == authUserId,
                  })
              .toList(),
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
