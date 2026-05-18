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

  String _normalizeEntity(String value) {
    switch (value.trim().toLowerCase()) {
      case 'groups':
      case 'group':
        return 'groups';
      case 'users':
      case 'blingers':
      default:
        return 'users';
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
    required String entity,
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
    return entity == 'groups'
        ? _buildGroupBaseQuery(
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
          )
        : _buildUserBaseQuery(
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
  }

  ({String sql, List<dynamic> args, String scopeValue}) _buildUserBaseQuery({
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
      where.add('COALESCE(u.is_verified, 0) = 1');
    }

    if (search.trim().isNotEmpty) {
      final searchParam = addArg('%${search.trim()}%');
      where.add(
        '(LOWER(u.name) LIKE LOWER($searchParam) OR LOWER(u.username) LIKE LOWER($searchParam))',
      );
    }

    final scopeValue = _applyUserScopeFilters(
      scope: scope,
      where: where,
      addArg: addArg,
      viewerLocation: viewerLocation,
      requestedContinent: requestedContinent,
      requestedCountry: requestedCountry,
      requestedCountryCode: requestedCountryCode,
      requestedCity: requestedCity,
      tableAlias: 'u',
    );

    final whereClause = where.join(' AND ');
    final dateCondition = _periodDateCondition(period);
    final sql = period == 'all_time'
        ? _buildUserAllTimeQuery(
            whereClause: whereClause,
            followingJoin: followingJoin,
          )
        : _buildUserTimedQuery(
            whereClause: whereClause,
            followingJoin: followingJoin,
            dateCondition: dateCondition,
          );

    return (sql: sql, args: args, scopeValue: scopeValue);
  }

  ({String sql, List<dynamic> args, String scopeValue}) _buildGroupBaseQuery({
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

    final where = <String>['g.is_active = 1', 'm.deleted_at IS NULL'];
    var followingJoin = '';
    var myMembershipExpression = 'false';
    var myOwnershipExpression = 'false';

    if (followingOnly && authUserId.isNotEmpty) {
      final followerParam = addArg(authUserId);
      followingJoin =
          'INNER JOIN follows f ON f.following_id = m.id AND f.follower_id = $followerParam';
    }

    if (verifiedOnly) {
      where.add('COALESCE(creator.is_verified, 0) = 1');
    }

    if (search.trim().isNotEmpty) {
      final searchParam = addArg('%${search.trim()}%');
      where.add(
        '(LOWER(g.name) LIKE LOWER($searchParam) OR LOWER(COALESCE(g.description, \'\')) LIKE LOWER($searchParam))',
      );
    }

    final scopeValue = _applyUserScopeFilters(
      scope: scope,
      where: where,
      addArg: addArg,
      viewerLocation: viewerLocation,
      requestedContinent: requestedContinent,
      requestedCountry: requestedCountry,
      requestedCountryCode: requestedCountryCode,
      requestedCity: requestedCity,
      tableAlias: 'm',
    );

    if (authUserId.isNotEmpty) {
      final memberParam = addArg(authUserId);
      myMembershipExpression = '''
        EXISTS(
          SELECT 1
          FROM group_members gm_self
          WHERE TRIM(gm_self.group_id) = TRIM(g.id::text)
            AND TRIM(gm_self.user_id) = TRIM($memberParam)
            AND gm_self.status = 'active'
        )
      ''';
      final ownerParam = addArg(authUserId);
      myOwnershipExpression = 'TRIM(g.created_by) = TRIM($ownerParam)';
    }

    final whereClause = where.join(' AND ');
    final dateCondition = _periodDateCondition(period);
    final sql = period == 'all_time'
        ? _buildGroupAllTimeQuery(
            whereClause: whereClause,
            followingJoin: followingJoin,
            myMembershipExpression: myMembershipExpression,
            myOwnershipExpression: myOwnershipExpression,
          )
        : _buildGroupTimedQuery(
            whereClause: whereClause,
            followingJoin: followingJoin,
            myMembershipExpression: myMembershipExpression,
            myOwnershipExpression: myOwnershipExpression,
            dateCondition: dateCondition,
          );

    return (sql: sql, args: args, scopeValue: scopeValue);
  }

  String _applyUserScopeFilters({
    required String scope,
    required List<String> where,
    required String Function(dynamic value) addArg,
    required Map<String, dynamic> viewerLocation,
    required String requestedContinent,
    required String requestedCountry,
    required String requestedCountryCode,
    required String requestedCity,
    required String tableAlias,
  }) {
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
            'LOWER(COALESCE($tableAlias.continent, \'\')) = LOWER($continentParam)',
          );
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
            'UPPER(COALESCE($tableAlias.country_code, \'\')) = UPPER($countryCodeParam)',
          );
        } else if (chosenCountry.isNotEmpty) {
          final countryParam = addArg(chosenCountry);
          where.add(
            'LOWER(COALESCE($tableAlias.country, \'\')) = LOWER($countryParam)',
          );
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
          where.add(
            'LOWER(COALESCE($tableAlias.city, \'\')) = LOWER($cityParam)',
          );
          if (chosenCountryCode.isNotEmpty) {
            final countryCodeParam = addArg(chosenCountryCode);
            where.add(
              'UPPER(COALESCE($tableAlias.country_code, \'\')) = UPPER($countryCodeParam)',
            );
          }
        }
        break;
    }
    return scopeValue;
  }

  String _buildUserAllTimeQuery({
    required String whereClause,
    required String followingJoin,
  }) {
    return '''
      SELECT
        u.id,
        u.name,
        u.username,
        u.avatar,
        COALESCE(u.is_verified, 0) = 1 AS is_verified,
        u.city,
        u.region,
        u.country,
        u.country_code,
        u.continent,
        COALESCE(u.bling_score, 0) AS score,
        COALESCE(w.balance, 0) AS bling_balance,
        0 AS member_count,
        false AS is_member,
        false AS is_owner,
        'user' AS entry_type
      FROM users u
      LEFT JOIN wallets w ON w.user_id = u.id
      $followingJoin
      WHERE $whereClause
    ''';
  }

  String _buildUserTimedQuery({
    required String whereClause,
    required String followingJoin,
    required String dateCondition,
  }) {
    return '''
      WITH post_scores AS (
        SELECT
          p.user_id,
          COALESCE(SUM(COALESCE(post_likes.like_count, 0)), 0) AS post_score
        FROM posts p
        LEFT JOIN (
          SELECT post_id, COUNT(*) AS like_count
          FROM likes
          GROUP BY post_id
        ) post_likes ON post_likes.post_id = p.id
        WHERE p.created_at $dateCondition
        GROUP BY p.user_id
      ),
      challenge_scores AS (
        SELECT ce.user_id, COUNT(DISTINCT ce.id) * 5 AS challenge_score
        FROM challenge_entries ce
        WHERE ce.created_at $dateCondition
        GROUP BY ce.user_id
      )
      SELECT
        u.id,
        u.name,
        u.username,
        u.avatar,
        COALESCE(u.is_verified, 0) = 1 AS is_verified,
        u.city,
        u.region,
        u.country,
        u.country_code,
        u.continent,
        COALESCE(post_scores.post_score, 0) + COALESCE(challenge_scores.challenge_score, 0) AS score,
        COALESCE(w.balance, 0) AS bling_balance,
        0 AS member_count,
        false AS is_member,
        false AS is_owner,
        'user' AS entry_type
      FROM users u
      LEFT JOIN wallets w ON w.user_id = u.id
      LEFT JOIN post_scores ON post_scores.user_id = u.id
      LEFT JOIN challenge_scores ON challenge_scores.user_id = u.id
      $followingJoin
      WHERE $whereClause
    ''';
  }

  String _buildGroupAllTimeQuery({
    required String whereClause,
    required String followingJoin,
    required String myMembershipExpression,
    required String myOwnershipExpression,
  }) {
    return '''
      SELECT
        g.id,
        g.name,
        '' AS username,
        g.avatar,
        COALESCE(creator.is_verified, 0) = 1 AS is_verified,
        COALESCE(NULLIF(g.discoverable_area, ''), MAX(COALESCE(m.city, ''))) AS city,
        '' AS region,
        COALESCE(NULLIF(g.discoverable_country, ''), MAX(COALESCE(m.country, ''))) AS country,
        MAX(COALESCE(m.country_code, '')) AS country_code,
        MAX(COALESCE(m.continent, '')) AS continent,
        COALESCE(SUM(COALESCE(m.bling_score, 0)), 0) AS score,
        COALESCE(SUM(COALESCE(w.balance, 0)), 0) AS bling_balance,
        COUNT(DISTINCT m.id) AS member_count,
        $myMembershipExpression AS is_member,
        $myOwnershipExpression AS is_owner,
        'group' AS entry_type
      FROM groups g
      JOIN group_members gm
        ON TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'active'
      JOIN users m ON TRIM(m.id) = TRIM(gm.user_id)
      LEFT JOIN wallets w ON w.user_id = m.id
      LEFT JOIN users creator ON TRIM(creator.id) = TRIM(g.created_by)
      $followingJoin
      WHERE $whereClause
      GROUP BY
        g.id, g.name, g.avatar, creator.is_verified,
        g.discoverable_area, g.discoverable_country, g.created_by
      HAVING COUNT(DISTINCT m.id) > 0
    ''';
  }

  String _buildGroupTimedQuery({
    required String whereClause,
    required String followingJoin,
    required String myMembershipExpression,
    required String myOwnershipExpression,
    required String dateCondition,
  }) {
    return '''
      WITH post_scores AS (
        SELECT
          p.user_id,
          COALESCE(SUM(COALESCE(post_likes.like_count, 0)), 0) AS post_score
        FROM posts p
        LEFT JOIN (
          SELECT post_id, COUNT(*) AS like_count
          FROM likes
          GROUP BY post_id
        ) post_likes ON post_likes.post_id = p.id
        WHERE p.created_at $dateCondition
        GROUP BY p.user_id
      ),
      challenge_scores AS (
        SELECT ce.user_id, COUNT(DISTINCT ce.id) * 5 AS challenge_score
        FROM challenge_entries ce
        WHERE ce.created_at $dateCondition
        GROUP BY ce.user_id
      )
      SELECT
        g.id,
        g.name,
        '' AS username,
        g.avatar,
        COALESCE(creator.is_verified, 0) = 1 AS is_verified,
        COALESCE(NULLIF(g.discoverable_area, ''), MAX(COALESCE(m.city, ''))) AS city,
        '' AS region,
        COALESCE(NULLIF(g.discoverable_country, ''), MAX(COALESCE(m.country, ''))) AS country,
        MAX(COALESCE(m.country_code, '')) AS country_code,
        MAX(COALESCE(m.continent, '')) AS continent,
        COALESCE(SUM(COALESCE(post_scores.post_score, 0) + COALESCE(challenge_scores.challenge_score, 0)), 0) AS score,
        COALESCE(SUM(COALESCE(w.balance, 0)), 0) AS bling_balance,
        COUNT(DISTINCT m.id) AS member_count,
        $myMembershipExpression AS is_member,
        $myOwnershipExpression AS is_owner,
        'group' AS entry_type
      FROM groups g
      JOIN group_members gm
        ON TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'active'
      JOIN users m ON TRIM(m.id) = TRIM(gm.user_id)
      LEFT JOIN wallets w ON w.user_id = m.id
      LEFT JOIN users creator ON TRIM(creator.id) = TRIM(g.created_by)
      LEFT JOIN post_scores ON TRIM(post_scores.user_id) = TRIM(m.id)
      LEFT JOIN challenge_scores ON TRIM(challenge_scores.user_id) = TRIM(m.id)
      $followingJoin
      WHERE $whereClause
      GROUP BY
        g.id, g.name, g.avatar, creator.is_verified,
        g.discoverable_area, g.discoverable_country, g.created_by
      HAVING COUNT(DISTINCT m.id) > 0
    ''';
  }

  List<Map<String, dynamic>> _serializeLeaderboardRows(
    List<dynamic> rows,
    String authUserId,
  ) {
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .map((row) {
      final entryType = row['entry_type']?.toString() ?? 'user';
      final isGroup = entryType == 'group';
      return <String, dynamic>{
        'rank': _asInt(row['rank']),
        'id': row['id']?.toString() ?? '',
        'name': row['name']?.toString() ?? '',
        'username': row['username']?.toString() ?? '',
        'avatar': row['avatar']?.toString() ?? '',
        'is_verified': row['is_verified'] == true || row['is_verified'] == 1,
        'score': _asInt(row['score']),
        'bling_balance': _asInt(row['bling_balance']),
        'member_count': _asInt(row['member_count']),
        'is_member': row['is_member'] == true || row['is_member'] == 1,
        'is_owner': row['is_owner'] == true || row['is_owner'] == 1,
        'is_me': !isGroup && (row['id']?.toString() ?? '') == authUserId,
        'entry_type': entryType,
        'continent': row['continent']?.toString() ?? '',
        'country': row['country']?.toString() ?? '',
        'country_code': row['country_code']?.toString() ?? '',
        'city': row['city']?.toString() ?? '',
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> _resolveMyEntry({
    required String entity,
    required String baseSql,
    required List<dynamic> queryArgs,
    required String rankingOrder,
    required String authUserId,
  }) async {
    if (authUserId.isEmpty) return null;

    if (entity == 'groups') {
      final rows = await connection!.select(
        '''
        WITH ranked AS (
          SELECT
            base.*,
            ROW_NUMBER() OVER (ORDER BY $rankingOrder) AS rank
          FROM ($baseSql) base
        )
        SELECT *
        FROM ranked
        WHERE is_member = true OR is_owner = true
        ORDER BY is_owner DESC, rank ASC
        LIMIT 1
        ''',
        queryArgs,
      );
      if (rows.isEmpty) return null;
      final serialized = _serializeLeaderboardRows(rows, authUserId);
      return serialized.isEmpty ? null : serialized.first;
    }

    final myRankArgs = List<dynamic>.from(queryArgs)..add(authUserId);
    final authPlaceholder = '\$${myRankArgs.length}';
    final myRows = await connection!.select(
      '''
      WITH ranked AS (
        SELECT
          base.*,
          ROW_NUMBER() OVER (ORDER BY $rankingOrder) AS rank
        FROM ($baseSql) base
      )
      SELECT *
      FROM ranked
      WHERE id = $authPlaceholder
      LIMIT 1
      ''',
      myRankArgs,
    );
    if (myRows.isEmpty) return null;
    final serialized = _serializeLeaderboardRows(myRows, authUserId);
    return serialized.isEmpty ? null : serialized.first;
  }

  /// GET /api/leaderboard
  /// entity=users|groups
  /// scope=global|continent|country|city
  /// period=all_time|daily|weekly|monthly
  Future<Response> getLeaderboard(Request request) async {
    final entity =
        _normalizeEntity(request.input('entity')?.toString() ?? 'users');
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
        entity: entity,
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
            'entity': entity,
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

      final myEntry = await _resolveMyEntry(
        entity: entity,
        baseSql: query.sql,
        queryArgs: query.args,
        rankingOrder: rankingOrder,
        authUserId: authUserId,
      );
      final myRank = myEntry == null ? null : _asInt(myEntry['rank']);

      final countRows = await connection!.select(
        'SELECT COUNT(*) AS cnt FROM (${query.sql}) base',
        query.args,
      );
      final totalCount = countRows.isEmpty ? 0 : _asInt(countRows.first['cnt']);

      return Response.json({
        'leaderboard': {
          'entity': entity,
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
