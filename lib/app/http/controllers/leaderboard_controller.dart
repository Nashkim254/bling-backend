import 'dart:io';

import 'package:bling/support/location_scope_helper.dart';
import 'package:vania/vania.dart';

class LeaderboardController extends Controller {
  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  String _authUserId(Request request) {
    final requestUserId = request.input('auth_user_id')?.toString() ?? '';
    if (requestUserId.isNotEmpty) return requestUserId;
    return Auth().id()?.toString() ?? '';
  }

  String _normalizePeriod(String value) {
    switch (value.trim().toLowerCase()) {
      case 'daily':
        return 'daily';
      case 'weekly':
        return 'weekly';
      case 'monthly':
        return 'monthly';
      case 'all_time':
      case 'alltime':
      case 'global':
      default:
        return 'all_time';
    }
  }

  String _normalizeScope(String value) {
    switch (value.trim().toLowerCase()) {
      case 'continent':
        return 'continent';
      case 'country':
        return 'country';
      case 'city':
        return 'city';
      case 'global':
      default:
        return 'global';
    }
  }

  String _scoreOrderExpression(String sortBy) {
    return sortBy == 'balance'
        ? 'COALESCE(bling_balance, 0) DESC NULLS LAST, COALESCE(score, 0) DESC NULLS LAST, name ASC, id ASC'
        : 'COALESCE(score, 0) DESC NULLS LAST, COALESCE(bling_balance, 0) DESC NULLS LAST, name ASC, id ASC';
  }

  String _periodDateCondition(String period) {
    switch (period) {
      case 'daily':
        return ">= NOW() - INTERVAL '1 day'";
      case 'weekly':
        return ">= NOW() - INTERVAL '7 days'";
      case 'monthly':
        return ">= NOW() - INTERVAL '30 days'";
      default:
        return '';
    }
  }

  Future<Map<String, dynamic>> _viewerLocationContext(String authUserId) async {
    if (authUserId.isEmpty) {
      return <String, dynamic>{
        'has_location': false,
        'continent': '',
        'country': '',
        'country_code': '',
        'city': '',
      };
    }

    final rows = await connection!.select(
      '''
      SELECT continent, country, country_code, city
      FROM users
      WHERE id = \$1
      LIMIT 1
      ''',
      [authUserId],
    );

    if (rows.isEmpty) {
      return <String, dynamic>{
        'has_location': false,
        'continent': '',
        'country': '',
        'country_code': '',
        'city': '',
      };
    }

    final row = Map<String, dynamic>.from(rows.first as Map);
    final continent =
        LocationScopeHelper.normalizeText(row['continent']?.toString() ?? '');
    final country =
        LocationScopeHelper.normalizeText(row['country']?.toString() ?? '');
    final countryCode = LocationScopeHelper.normalizeCountryCode(
      row['country_code']?.toString() ?? '',
    );
    final city =
        LocationScopeHelper.normalizeText(row['city']?.toString() ?? '');

    return <String, dynamic>{
      'has_location':
          continent.isNotEmpty || countryCode.isNotEmpty || city.isNotEmpty,
      'continent': continent,
      'country': country,
      'country_code': countryCode,
      'city': city,
    };
  }

  ({String sql, List<dynamic> args, String scopeValue}) _buildBaseQuery({
    required String period,
    required String scope,
    required String sortBy,
    required bool followingOnly,
    required bool verifiedOnly,
    required String search,
    required String authUserId,
    required Map<String, dynamic> viewerLocation,
    required String requestedContinent,
    required String requestedCountry,
    required String requestedCountryCode,
    required String requestedCity,
  }) {
    final args = <dynamic>[];
    String addArg(dynamic value) {
      args.add(value);
      return '\$${args.length}';
    }

    final where = <String>['u.deleted_at IS NULL'];
    var followingJoin = '';

    if (followingOnly && authUserId.isNotEmpty) {
      final followerParam = addArg(authUserId);
      followingJoin =
          'INNER JOIN follows f ON f.following_id = u.id AND f.follower_id = $followerParam';
    }

    if (verifiedOnly) {
      where.add('u.is_verified = true');
    }

    if (search.trim().isNotEmpty) {
      final searchParam = addArg('%${search.trim()}%');
      where.add(
        '(LOWER(u.name) LIKE LOWER($searchParam) OR LOWER(u.username) LIKE LOWER($searchParam))',
      );
    }

    String scopeValue = '';
    switch (scope) {
      case 'continent':
        scopeValue = LocationScopeHelper.normalizeText(
          requestedContinent.isNotEmpty
              ? requestedContinent
              : viewerLocation['continent']?.toString() ?? '',
        );
        if (scopeValue.isNotEmpty) {
          final continentParam = addArg(scopeValue);
          where.add(
              'LOWER(COALESCE(u.continent, \'\')) = LOWER($continentParam)');
        }
        break;
      case 'country':
        final chosenCountryCode = LocationScopeHelper.normalizeCountryCode(
          requestedCountryCode.isNotEmpty
              ? requestedCountryCode
              : viewerLocation['country_code']?.toString() ?? '',
        );
        final chosenCountry = LocationScopeHelper.normalizeText(
          requestedCountry.isNotEmpty
              ? requestedCountry
              : viewerLocation['country']?.toString() ?? '',
        );
        scopeValue =
            chosenCountryCode.isNotEmpty ? chosenCountryCode : chosenCountry;
        if (chosenCountryCode.isNotEmpty) {
          final countryCodeParam = addArg(chosenCountryCode);
          where.add(
            'UPPER(COALESCE(u.country_code, \'\')) = UPPER($countryCodeParam)',
          );
        } else if (chosenCountry.isNotEmpty) {
          final countryParam = addArg(chosenCountry);
          where.add('LOWER(COALESCE(u.country, \'\')) = LOWER($countryParam)');
        }
        break;
      case 'city':
        final chosenCity = LocationScopeHelper.normalizeText(
          requestedCity.isNotEmpty
              ? requestedCity
              : viewerLocation['city']?.toString() ?? '',
        );
        final chosenCountryCode = LocationScopeHelper.normalizeCountryCode(
          requestedCountryCode.isNotEmpty
              ? requestedCountryCode
              : viewerLocation['country_code']?.toString() ?? '',
        );
        scopeValue = chosenCity;
        if (chosenCity.isNotEmpty) {
          final cityParam = addArg(chosenCity);
          where.add('LOWER(COALESCE(u.city, \'\')) = LOWER($cityParam)');
          if (chosenCountryCode.isNotEmpty) {
            final countryCodeParam = addArg(chosenCountryCode);
            where.add(
              'UPPER(COALESCE(u.country_code, \'\')) = UPPER($countryCodeParam)',
            );
          }
        }
        break;
    }

    final whereClause = where.join(' AND ');

    final baseSql = switch (period) {
      'daily' || 'weekly' || 'monthly' => _buildTimedLeaderboardQuery(
          whereClause: whereClause,
          followingJoin: followingJoin,
          dateCondition: _periodDateCondition(period),
        ),
      _ => _buildAllTimeLeaderboardQuery(
          whereClause: whereClause,
          followingJoin: followingJoin,
        ),
    };

    return (
      sql: baseSql,
      args: args,
      scopeValue: scopeValue,
    );
  }

  String _buildAllTimeLeaderboardQuery({
    required String whereClause,
    required String followingJoin,
  }) {
    return '''
      SELECT
        u.id,
        u.name,
        u.username,
        u.avatar,
        u.is_verified,
        u.city,
        u.region,
        u.country,
        u.country_code,
        u.continent,
        COALESCE(u.bling_score, 0) AS score,
        COALESCE(w.balance, 0) AS bling_balance
      FROM users u
      LEFT JOIN wallets w ON w.user_id = u.id
      $followingJoin
      WHERE $whereClause
    ''';
  }

  String _buildTimedLeaderboardQuery({
    required String whereClause,
    required String followingJoin,
    required String dateCondition,
  }) {
    return '''
      SELECT
        u.id,
        u.name,
        u.username,
        u.avatar,
        u.is_verified,
        u.city,
        u.region,
        u.country,
        u.country_code,
        u.continent,
        COALESCE(SUM(COALESCE(post_likes.like_count, 0)), 0) +
          COALESCE(COUNT(DISTINCT ce.id) * 5, 0) AS score,
        COALESCE(w.balance, 0) AS bling_balance
      FROM users u
      LEFT JOIN wallets w ON w.user_id = u.id
      LEFT JOIN posts p ON p.user_id = u.id AND p.created_at $dateCondition
      LEFT JOIN (
        SELECT post_id, COUNT(*) AS like_count
        FROM likes
        GROUP BY post_id
      ) post_likes ON post_likes.post_id = p.id
      LEFT JOIN challenge_entries ce
        ON ce.user_id = u.id AND ce.created_at $dateCondition
      $followingJoin
      WHERE $whereClause
      GROUP BY
        u.id, u.name, u.username, u.avatar, u.is_verified,
        u.city, u.region, u.country, u.country_code, u.continent,
        w.balance
    ''';
  }

  List<Map<String, dynamic>> _serializeLeaderboardRows(
    List<dynamic> rows,
    String authUserId,
  ) {
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .map((row) => <String, dynamic>{
              'rank': _asInt(row['rank']),
              'id': row['id']?.toString() ?? '',
              'name': row['name']?.toString() ?? '',
              'username': row['username']?.toString() ?? '',
              'avatar': row['avatar']?.toString() ?? '',
              'is_verified':
                  row['is_verified'] == true || row['is_verified'] == 1,
              'score': _asInt(row['score']),
              'bling_balance': _asInt(row['bling_balance']),
              'is_me': (row['id']?.toString() ?? '') == authUserId,
              'continent': row['continent']?.toString() ?? '',
              'country': row['country']?.toString() ?? '',
              'country_code': row['country_code']?.toString() ?? '',
              'city': row['city']?.toString() ?? '',
            })
        .toList();
  }

  /// GET /api/leaderboard
  /// scope=global|continent|country|city
  /// period=all_time|daily|weekly|monthly
  Future<Response> getLeaderboard(Request request) async {
    final scope =
        _normalizeScope(request.input('scope')?.toString() ?? 'global');
    final period = _normalizePeriod(
      request.input('period')?.toString() ?? 'all_time',
    );
    final sortBy =
        request.input('sort_by')?.toString() == 'balance' ? 'balance' : 'score';
    final followingOnly = request.input('following_only')?.toString() == 'true';
    final verifiedOnly = request.input('verified_only')?.toString() == 'true';
    final search = request.input('search')?.toString().trim() ?? '';
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '50') ?? 50;
    final authUserId = _authUserId(request);

    final requestedContinent =
        request.input('continent')?.toString().trim() ?? '';
    final requestedCountry = request.input('country')?.toString().trim() ?? '';
    final requestedCountryCode =
        request.input('country_code')?.toString().trim() ?? '';
    final requestedCity = request.input('city')?.toString().trim() ?? '';

    try {
      final viewerLocation = await _viewerLocationContext(authUserId);
      final query = _buildBaseQuery(
        period: period,
        scope: scope,
        sortBy: sortBy,
        followingOnly: followingOnly,
        verifiedOnly: verifiedOnly,
        search: search,
        authUserId: authUserId,
        viewerLocation: viewerLocation,
        requestedContinent: requestedContinent,
        requestedCountry: requestedCountry,
        requestedCountryCode: requestedCountryCode,
        requestedCity: requestedCity,
      );

      if (scope != 'global' && query.scopeValue.isEmpty) {
        return Response.json({
          'leaderboard': {
            'scope': scope,
            'scope_value': '',
            'period': period,
            'sort_by': sortBy,
            'page': page,
            'limit': limit,
            'total_count': 0,
            'my_rank': null,
            'my_entry': null,
            'location_context': viewerLocation,
            'data': <Map<String, dynamic>>[],
          }
        }, HttpStatus.ok);
      }

      final rankingOrder = _scoreOrderExpression(sortBy);
      final pagingArgs = List<dynamic>.from(query.args);
      pagingArgs.add(limit);
      final limitPlaceholder = '\$${pagingArgs.length}';
      pagingArgs.add((page - 1) * limit);
      final offsetPlaceholder = '\$${pagingArgs.length}';

      final pagedRows = await connection!.select(
        '''
        WITH ranked AS (
          SELECT
            base.*,
            ROW_NUMBER() OVER (ORDER BY $rankingOrder) AS rank
          FROM (${query.sql}) base
        )
        SELECT *
        FROM ranked
        ORDER BY rank ASC
        LIMIT $limitPlaceholder OFFSET $offsetPlaceholder
        ''',
        pagingArgs,
      );

      int? myRank;
      Map<String, dynamic>? myEntry;
      if (authUserId.isNotEmpty) {
        final myRankArgs = List<dynamic>.from(query.args)..add(authUserId);
        final authPlaceholder = '\$${myRankArgs.length}';
        final myRows = await connection!.select(
          '''
          WITH ranked AS (
            SELECT
              base.*,
              ROW_NUMBER() OVER (ORDER BY $rankingOrder) AS rank
            FROM (${query.sql}) base
          )
          SELECT *
          FROM ranked
          WHERE id = $authPlaceholder
          LIMIT 1
          ''',
          myRankArgs,
        );
        if (myRows.isNotEmpty) {
          final serializedRows = _serializeLeaderboardRows(myRows, authUserId);
          if (serializedRows.isNotEmpty) {
            myEntry = serializedRows.first;
            myRank = myEntry['rank'] as int?;
          }
        }
      }

      final countRows = await connection!.select(
        'SELECT COUNT(*) AS cnt FROM (${query.sql}) base',
        query.args,
      );
      final totalCount = countRows.isEmpty ? 0 : _asInt(countRows.first['cnt']);

      return Response.json({
        'leaderboard': {
          'scope': scope,
          'scope_value': query.scopeValue,
          'period': period,
          'sort_by': sortBy,
          'page': page,
          'limit': limit,
          'total_count': totalCount,
          'my_rank': myRank,
          'my_entry': myEntry,
          'location_context': viewerLocation,
          'data': _serializeLeaderboardRows(pagedRows, authUserId),
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
