import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class AdminController extends Controller {
  Future<Response> getDashboard(Request request) async {
    final totalAppBlingRows = await connection!.select(
      'SELECT COALESCE(SUM(balance), 0) AS total FROM wallets',
      [],
    );
    final todayRows = await connection!.select(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM bling_transactions
      WHERE type = 'purchase' AND DATE(created_at) = CURRENT_DATE
      ''',
      [],
    );
    final weekRows = await connection!.select(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM bling_transactions
      WHERE type = 'purchase' AND created_at >= NOW() - INTERVAL '7 days'
      ''',
      [],
    );
    final monthRows = await connection!.select(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM bling_transactions
      WHERE type = 'purchase' AND created_at >= NOW() - INTERVAL '30 days'
      ''',
      [],
    );
    final userStatsRows = await connection!.select(
      '''
      SELECT
        COUNT(*) FILTER (WHERE deleted_at IS NULL) AS total_users,
        COUNT(*) FILTER (WHERE deleted_at IS NULL AND status = 'active') AS active_users,
        COUNT(*) FILTER (WHERE deleted_at IS NULL AND status != 'active') AS inactive_users
      FROM users
      ''',
      [],
    );
    final monthlyPurchaseRows = await connection!.select(
      '''
      SELECT TO_CHAR(DATE_TRUNC('month', created_at), 'Mon') AS month,
             COALESCE(SUM(amount), 0) AS total
      FROM bling_transactions
      WHERE type = 'purchase'
        AND created_at >= DATE_TRUNC('year', CURRENT_DATE)
      GROUP BY DATE_TRUNC('month', created_at)
      ORDER BY DATE_TRUNC('month', created_at)
      ''',
      [],
    );
    final topUsersRows = await connection!.select(
      '''
      SELECT u.id, u.name, u.username, u.avatar, COALESCE(w.balance, 0) AS bling_balance,
             COALESCE(u.bling_score, 0) AS bling_score
      FROM users u
      LEFT JOIN wallets w ON w.user_id = u.id
      WHERE u.deleted_at IS NULL
      ORDER BY COALESCE(w.balance, 0) DESC, COALESCE(u.bling_score, 0) DESC
      LIMIT 10
      ''',
      [],
    );
    final levelStatsRows = await connection!.select(
      '''
      SELECT
        COUNT(*) FILTER (WHERE bling_score BETWEEN 0 AND 5) AS level_0_5_users,
        COUNT(*) FILTER (WHERE bling_score BETWEEN 6 AND 10) AS level_6_10_users,
        COUNT(*) FILTER (WHERE bling_score BETWEEN 11 AND 15) AS level_11_15_users,
        COALESCE(SUM(bling_score) FILTER (WHERE bling_score BETWEEN 0 AND 5), 0) AS level_0_5_bling,
        COALESCE(SUM(bling_score) FILTER (WHERE bling_score BETWEEN 6 AND 10), 0) AS level_6_10_bling,
        COALESCE(SUM(bling_score) FILTER (WHERE bling_score BETWEEN 11 AND 15), 0) AS level_11_15_bling
      FROM users
      WHERE deleted_at IS NULL
      ''',
      [],
    );

    final userStats = userStatsRows.first;
    final levelStats = levelStatsRows.first;

    return Response.json({
      'stats': {
        'total_app_bling': _toInt(totalAppBlingRows.first['total']),
        'bling_bought_today': _toInt(todayRows.first['total']),
        'bling_bought_this_week': _toInt(weekRows.first['total']),
        'bling_bought_this_month': _toInt(monthRows.first['total']),
        'total_users': _toInt(userStats['total_users']),
        'active_users': _toInt(userStats['active_users']),
        'inactive_users': _toInt(userStats['inactive_users']),
      },
      'purchase_trend': monthlyPurchaseRows
          .map((row) => {
                'month': row['month']?.toString() ?? '',
                'total': _toInt(row['total']),
              })
          .toList(),
      'top_users': topUsersRows
          .asMap()
          .entries
          .map((entry) => {
                'rank': entry.key + 1,
                'id': entry.value['id']?.toString() ?? '',
                'name': _cleanString(entry.value['name']),
                'username': _cleanString(entry.value['username']),
                'avatar': _cleanString(entry.value['avatar']),
                'bling_balance': _toInt(entry.value['bling_balance']),
                'bling_score': _toInt(entry.value['bling_score']),
              })
          .toList(),
      'level_stats': {
        'level_0_5_users': _toInt(levelStats['level_0_5_users']),
        'level_6_10_users': _toInt(levelStats['level_6_10_users']),
        'level_11_15_users': _toInt(levelStats['level_11_15_users']),
        'level_0_5_bling': _toInt(levelStats['level_0_5_bling']),
        'level_6_10_bling': _toInt(levelStats['level_6_10_bling']),
        'level_11_15_bling': _toInt(levelStats['level_11_15_bling']),
      }
    }, 200);
  }

  Future<Response> getRoles(Request request) async {
    final rows = await connection!.select(
      '''
      SELECT r.id, r.name, r.description, r.permissions, r.status, r.created_at,
             COUNT(aur.user_id) AS users_count
      FROM admin_roles r
      LEFT JOIN admin_user_roles aur ON aur.role_id = r.id
      GROUP BY r.id
      ORDER BY r.created_at ASC
      ''',
      [],
    );

    return Response.json({
      'roles': rows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'name': _cleanString(row['name']),
                'description': _cleanString(row['description']),
                'permissions': _decodeStringList(row['permissions']),
                'status': _cleanString(row['status'], fallback: 'active'),
                'created_at': row['created_at']?.toString() ?? '',
                'users_count': _toInt(row['users_count']),
              })
          .toList(),
    }, 200);
  }

  Future<Response> createRole(Request request) async {
    request.validate({
      'name': 'required|string',
      'description': 'required|string',
    }, {
      'name.required': 'Role name is required',
      'description.required': 'Description is required',
    });

    final body = request.body;
    final permissions = body['permissions'] is List
        ? (body['permissions'] as List).map((item) => item.toString()).toList()
        : <String>[];
    final roleId = const Uuid().v4();
    final adminId = request.input('auth_admin_id')?.toString() ?? '';

    await connection!.statement(
      '''
      INSERT INTO admin_roles (id, name, description, permissions, status, created_by, created_at, updated_at)
      VALUES (\$1, \$2, \$3, \$4, 'active', \$5, NOW(), NOW())
      ''',
      [
        roleId,
        body['name'],
        body['description'],
        jsonEncode(permissions),
        adminId.isEmpty ? null : adminId,
      ],
    );

    return Response.json({'message': 'Role created', 'id': roleId}, 201);
  }

  Future<Response> toggleRoleStatus(Request request, [dynamic _]) async {
    final roleId = request.params()['id']?.toString() ?? '';
    if (roleId.isEmpty) {
      return Response.json({'message': 'Role not found'}, 404);
    }

    final roleRows = await connection!.select(
      'SELECT status FROM admin_roles WHERE id = \$1 LIMIT 1',
      [roleId],
    );
    if (roleRows.isEmpty) {
      return Response.json({'message': 'Role not found'}, 404);
    }

    final nextStatus = roleRows.first['status']?.toString() == 'active'
        ? 'inactive'
        : 'active';
    await connection!.statement(
      'UPDATE admin_roles SET status = \$2, updated_at = NOW() WHERE id = \$1',
      [roleId, nextStatus],
    );

    return Response.json(
        {'message': 'Role updated', 'status': nextStatus}, 200);
  }

  Future<Response> getSystemUsers(Request request) async {
    final rows = await connection!.select(
      '''
      SELECT u.id, u.name, u.email, u.msisdn, u.status, u.created_at,
             COALESCE(
               JSON_AGG(r.name) FILTER (WHERE r.name IS NOT NULL),
               '[]'::json
             ) AS roles
      FROM users u
      LEFT JOIN admin_user_roles aur ON TRIM(aur.user_id) = TRIM(u.id)
      LEFT JOIN admin_roles r ON r.id = aur.role_id
      WHERE u.is_admin = 1 AND u.deleted_at IS NULL
      GROUP BY u.id, u.name, u.email, u.msisdn, u.status, u.created_at
      ORDER BY u.created_at ASC
      ''',
      [],
    );

    return Response.json({
      'users': rows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'name': _cleanString(row['name']),
                'phone': _cleanString(row['msisdn']),
                'email': _cleanString(row['email']),
                'status': _cleanString(row['status'], fallback: 'active'),
                'created_at': row['created_at']?.toString() ?? '',
                'roles': _decodeMaybeJsonArray(row['roles']),
              })
          .toList(),
    }, 200);
  }

  Future<Response> createSystemUser(Request request) async {
    request.validate({
      'name': 'required|string',
      'email': 'required|email',
    }, {
      'name.required': 'User name is required',
      'email.required': 'Email is required',
    });

    final body = request.body;
    final email = body['email']?.toString() ?? '';
    final existing = await connection!.select(
      'SELECT id FROM users WHERE email = \$1 LIMIT 1',
      [email],
    );
    if (existing.isNotEmpty) {
      return Response.json({'message': 'Email already in use'}, 409);
    }

    final userId = const Uuid().v4();
    final username = _slugify(body['name']?.toString() ?? 'admin') +
        userId.substring(0, 4).toLowerCase();
    final tempPassword = 'Admin@12345';

    await connection!.statement(
      '''
      INSERT INTO users (
        id, name, username, email, msisdn, password, avatar, cover_image, bio,
        account_type, bling_score, is_verified, status, is_admin, created_at, updated_at
      )
      VALUES (
        \$1, \$2, \$3, \$4, \$5, \$6, '', '', '',
        'private', 0, 1, 'active', 1, NOW(), NOW()
      )
      ''',
      [
        userId,
        body['name'],
        username,
        email,
        body['phone']?.toString() ?? '',
        Hash().make(tempPassword),
      ],
    );

    final roleNames = body['roles'] is List
        ? (body['roles'] as List).map((item) => item.toString()).toList()
        : <String>[];
    for (final roleName in roleNames) {
      final roleRows = await connection!.select(
        'SELECT id FROM admin_roles WHERE LOWER(name) = LOWER(\$1) LIMIT 1',
        [roleName],
      );
      if (roleRows.isEmpty) continue;
      await connection!.statement(
        '''
        INSERT INTO admin_user_roles (id, user_id, role_id, created_at, updated_at)
        SELECT \$1, \$2, \$3, NOW(), NOW()
        WHERE NOT EXISTS (
          SELECT 1 FROM admin_user_roles WHERE user_id = \$2 AND role_id = \$3
        )
        ''',
        [const Uuid().v4(), userId, roleRows.first['id']],
      );
    }

    return Response.json({
      'message': 'Admin user created',
      'id': userId,
      'temporary_password': tempPassword,
    }, 201);
  }

  Future<Response> toggleSystemUserStatus(Request request, [dynamic _]) async {
    final userId = request.params()['id']?.toString() ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'User not found'}, 404);
    }

    final rows = await connection!.select(
      'SELECT status FROM users WHERE id = \$1 AND is_admin = 1 LIMIT 1',
      [userId],
    );
    if (rows.isEmpty) {
      return Response.json({'message': 'User not found'}, 404);
    }

    final nextStatus =
        rows.first['status']?.toString() == 'active' ? 'disabled' : 'active';
    await connection!.statement(
      'UPDATE users SET status = \$2, updated_at = NOW() WHERE id = \$1',
      [userId, nextStatus],
    );

    return Response.json(
        {'message': 'User updated', 'status': nextStatus}, 200);
  }

  Future<Response> getAvatars(Request request) async {
    final rows = await connection!.select(
      '''
      SELECT a.id, a.name, a.image_url, a.price_bling, a.is_paid, a.owners_count,
             a.eligible_blingers, a.status,
             COUNT(ac.id) AS accessories_count
      FROM avatar_resources a
      LEFT JOIN avatar_accessories ac ON ac.avatar_id = a.id AND ac.status = 'active'
      GROUP BY a.id
      ORDER BY a.created_at DESC
      ''',
      [],
    );

    return Response.json({
      'avatars': rows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'name': _cleanString(row['name']),
                'image_url': _cleanString(row['image_url']),
                'price_bling': _toInt(row['price_bling']),
                'is_paid': _toInt(row['is_paid']) == 1,
                'owners_count': _toInt(row['owners_count']),
                'eligible_blingers': _cleanString(row['eligible_blingers']),
                'status': _cleanString(row['status'], fallback: 'active'),
                'accessories_count': _toInt(row['accessories_count']),
              })
          .toList(),
    }, 200);
  }

  Future<Response> createAvatar(Request request) async {
    final body = request.body;
    final avatarId = const Uuid().v4();
    await connection!.statement(
      '''
      INSERT INTO avatar_resources (
        id, name, image_url, price_bling, is_paid, owners_count,
        eligible_blingers, status, created_by, created_at, updated_at
      )
      VALUES (
        \$1, \$2, \$3, \$4, \$5, 0, \$6, 'active', \$7, NOW(), NOW()
      )
      ''',
      [
        avatarId,
        body['name']?.toString() ?? 'Avatar',
        body['image_url']?.toString() ?? '',
        _toInt(body['price_bling']),
        body['is_paid'] == true ? 1 : 0,
        body['eligible_blingers']?.toString() ?? 'All / above level 2 etc',
        (() {
          final adminId = request.input('auth_admin_id')?.toString() ?? '';
          return adminId.isEmpty ? null : adminId;
        })(),
      ],
    );
    return Response.json({'message': 'Avatar created', 'id': avatarId}, 201);
  }

  Future<Response> getAvatar(Request request, [dynamic _]) async {
    final avatarId = request.params()['id']?.toString() ?? '';
    final avatarRows = await connection!.select(
      'SELECT * FROM avatar_resources WHERE id = \$1 LIMIT 1',
      [avatarId],
    );
    if (avatarRows.isEmpty) {
      return Response.json({'message': 'Avatar not found'}, 404);
    }

    final accessoryRows = await connection!.select(
      'SELECT * FROM avatar_accessories WHERE avatar_id = \$1 AND status = \'active\' ORDER BY created_at ASC',
      [avatarId],
    );

    final userRows = await connection!.select(
      '''
      SELECT id, name, username
      FROM users
      WHERE avatar = \$1
      ORDER BY created_at DESC
      LIMIT 20
      ''',
      [avatarRows.first['image_url']?.toString() ?? ''],
    );

    return Response.json({
      'avatar': {
        'id': avatarRows.first['id']?.toString() ?? '',
        'name': _cleanString(avatarRows.first['name']),
        'image_url': _cleanString(avatarRows.first['image_url']),
        'price_bling': _toInt(avatarRows.first['price_bling']),
        'is_paid': _toInt(avatarRows.first['is_paid']) == 1,
        'owners_count': _toInt(avatarRows.first['owners_count']),
        'eligible_blingers':
            _cleanString(avatarRows.first['eligible_blingers']),
        'status': _cleanString(avatarRows.first['status'], fallback: 'active'),
      },
      'accessories': accessoryRows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'name': _cleanString(row['name']),
                'image_url': _cleanString(row['image_url']),
                'price_bling': _toInt(row['price_bling']),
                'is_paid': _toInt(row['is_paid']) == 1,
                'owners_count': _toInt(row['owners_count']),
                'eligible_blingers': _cleanString(row['eligible_blingers']),
              })
          .toList(),
      'users': userRows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'name': _cleanString(row['name']),
                'username': _cleanString(row['username']),
              })
          .toList(),
    }, 200);
  }

  Future<Response> createAccessory(Request request, [dynamic _]) async {
    final avatarId = request.params()['id']?.toString() ?? '';
    final body = request.body;
    final accessoryId = const Uuid().v4();
    await connection!.statement(
      '''
      INSERT INTO avatar_accessories (
        id, avatar_id, name, image_url, price_bling, is_paid, owners_count,
        eligible_blingers, status, created_by, created_at, updated_at
      )
      VALUES (
        \$1, \$2, \$3, \$4, \$5, \$6, 0, \$7, 'active', \$8, NOW(), NOW()
      )
      ''',
      [
        accessoryId,
        avatarId,
        body['name']?.toString() ?? 'Accessory',
        body['image_url']?.toString() ?? '',
        _toInt(body['price_bling']),
        body['is_paid'] == true ? 1 : 0,
        body['eligible_blingers']?.toString() ?? 'All / above level 2 etc',
        (() {
          final adminId = request.input('auth_admin_id')?.toString() ?? '';
          return adminId.isEmpty ? null : adminId;
        })(),
      ],
    );

    return Response.json(
        {'message': 'Accessory created', 'id': accessoryId}, 201);
  }

  Future<Response> getLeaderboards(Request request) async {
    final rows = await connection!.select(
      '''
      SELECT id, name, metric, users_limit, status, created_at
      FROM admin_leaderboards
      WHERE status = 'active'
      ORDER BY created_at ASC
      ''',
      [],
    );

    final leaderboards = <Map<String, dynamic>>[];
    for (final row in rows) {
      final metric = row['metric']?.toString() ?? 'bling';
      final previewUsers = await _fetchLeaderboardUsers(metric, 6);
      leaderboards.add({
        'id': row['id']?.toString() ?? '',
        'name': _cleanString(row['name']),
        'metric': _cleanString(metric, fallback: 'bling'),
        'users_limit': _toInt(row['users_limit']),
        'status': _cleanString(row['status'], fallback: 'active'),
        'created_at': row['created_at']?.toString() ?? '',
        'preview_users': previewUsers,
      });
    }

    return Response.json({'leaderboards': leaderboards}, 200);
  }

  Future<Response> createLeaderboard(Request request) async {
    request.validate({
      'name': 'required|string',
      'metric': 'required|string',
      'users_limit': 'required',
    }, {
      'name.required': 'Leaderboard name is required',
      'metric.required': 'Metric is required',
      'users_limit.required': 'Users limit is required',
    });

    final body = request.body;
    final leaderboardId = const Uuid().v4();
    final adminId = request.input('auth_admin_id')?.toString() ?? '';
    final metric =
        _normalizeLeaderboardMetric(body['metric']?.toString() ?? '');

    await connection!.statement(
      '''
      INSERT INTO admin_leaderboards (
        id, name, metric, users_limit, status, created_by, created_at, updated_at
      )
      VALUES (\$1, \$2, \$3, \$4, 'active', \$5, NOW(), NOW())
      ''',
      [
        leaderboardId,
        body['name']?.toString() ?? 'Leaderboard',
        metric,
        _toInt(body['users_limit']) <= 0 ? 20 : _toInt(body['users_limit']),
        adminId.isEmpty ? null : adminId,
      ],
    );

    return Response.json(
        {'message': 'Leaderboard created', 'id': leaderboardId}, 201);
  }

  Future<Response> getLeaderboard(Request request, [dynamic _]) async {
    final leaderboardId = request.params()['id']?.toString() ?? '';
    final rows = await connection!.select(
      'SELECT * FROM admin_leaderboards WHERE id = \$1 LIMIT 1',
      [leaderboardId],
    );
    if (rows.isEmpty) {
      return Response.json({'message': 'Leaderboard not found'}, 404);
    }

    final leaderboard = rows.first;
    final metric = leaderboard['metric']?.toString() ?? 'bling';
    final users = await _fetchLeaderboardUsers(
      metric,
      _toInt(leaderboard['users_limit']) <= 0
          ? 20
          : _toInt(leaderboard['users_limit']),
    );

    return Response.json({
      'leaderboard': {
        'id': leaderboard['id']?.toString() ?? '',
        'name': _cleanString(leaderboard['name']),
        'metric': _cleanString(metric, fallback: 'bling'),
        'users_limit': _toInt(leaderboard['users_limit']),
        'status': _cleanString(leaderboard['status'], fallback: 'active'),
      },
      'users': users,
    }, 200);
  }

  Future<Response> getLevels(Request request) async {
    final levels = await _loadLevels();
    return Response.json({'levels': levels}, 200);
  }

  Future<Response> createLevel(Request request) async {
    final body = request.body;
    final levelId = const Uuid().v4();
    final adminId = request.input('auth_admin_id')?.toString() ?? '';
    final levelRows = await connection!.select(
      'SELECT COALESCE(MAX(level_number), -1) AS max_level FROM admin_levels',
      [],
    );
    final nextLevelNumber = _toInt(levelRows.first['max_level']) + 1;
    final medals = body['medals'] is List
        ? (body['medals'] as List)
            .whereType<Map>()
            .map((item) =>
                item.map((key, value) => MapEntry(key.toString(), value)))
            .toList()
        : <Map<String, dynamic>>[];

    await connection!.statement(
      '''
      INSERT INTO admin_levels (
        id, level_number, name, required_bling, status, created_by, created_at, updated_at
      )
      VALUES (\$1, \$2, \$3, \$4, 'active', \$5, NOW(), NOW())
      ''',
      [
        levelId,
        nextLevelNumber,
        body['name']?.toString() ?? 'Level $nextLevelNumber',
        _toInt(body['required_bling']),
        adminId.isEmpty ? null : adminId,
      ],
    );

    await _replaceLevelMedals(levelId, medals, adminId);
    return Response.json({'message': 'Level created', 'id': levelId}, 201);
  }

  Future<Response> updateLevel(Request request, [dynamic _]) async {
    final levelId = request.params()['id']?.toString() ?? '';
    final body = request.body;
    final adminId = request.input('auth_admin_id')?.toString() ?? '';
    final medals = body['medals'] is List
        ? (body['medals'] as List)
            .whereType<Map>()
            .map((item) =>
                item.map((key, value) => MapEntry(key.toString(), value)))
            .toList()
        : <Map<String, dynamic>>[];

    await connection!.statement(
      '''
      UPDATE admin_levels
      SET name = \$2,
          required_bling = \$3,
          updated_at = NOW()
      WHERE id = \$1
      ''',
      [
        levelId,
        body['name']?.toString() ?? 'Level',
        _toInt(body['required_bling']),
      ],
    );

    await _replaceLevelMedals(levelId, medals, adminId);
    return Response.json({'message': 'Level updated'}, 200);
  }

  Future<Response> getLevel(Request request, [dynamic _]) async {
    final levelId = request.params()['id']?.toString() ?? '';
    final levels = await _loadLevels();
    final level = levels.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id']?.toString() == levelId,
          orElse: () => null,
        );

    if (level == null) {
      return Response.json({'message': 'Level not found'}, 404);
    }

    final users = await _fetchLevelUsers(
      _toInt(level['range_start']),
      level['range_end'] == null ? null : _toInt(level['range_end']),
    );

    return Response.json({
      'level': level,
      'users': users,
    }, 200);
  }

  Future<Response> getAdminNotifications(Request request) async {
    final rows = await connection!.select(
      '''
      SELECT n.id, n.type, n.title, n.body, n.is_read, n.created_at,
             n.user_id AS recipient_user_id,
             recipient.name AS recipient_user_name,
             recipient.username AS recipient_username,
             COALESCE(anc.status, 'pending') AS status,
             anc.processed_at,
             proc.name AS processed_by_name
      FROM notifications n
      LEFT JOIN users recipient ON TRIM(recipient.id) = TRIM(n.user_id)
      LEFT JOIN admin_notification_cases anc ON TRIM(anc.notification_id) = TRIM(n.id)
      LEFT JOIN users proc ON TRIM(proc.id) = TRIM(anc.processed_by)
      ORDER BY n.created_at DESC
      LIMIT 50
      ''',
      [],
    );

    return Response.json({
      'notifications': rows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'type': _cleanString(row['type']),
                'title': _cleanString(row['title']),
                'body': _cleanString(row['body']),
                'is_read': _toInt(row['is_read']) == 1,
                'created_at': row['created_at']?.toString() ?? '',
                'user_id': row['recipient_user_id']?.toString() ?? '',
                'user_name': _cleanString(row['recipient_user_name']),
                'username': _cleanString(row['recipient_username']),
                'status': _cleanString(row['status'], fallback: 'pending'),
                'processed_at': row['processed_at']?.toString() ?? '',
                'processed_by_name': _cleanString(row['processed_by_name']),
              })
          .toList(),
    }, 200);
  }

  Future<Response> processNotification(Request request, [dynamic _]) async {
    final notificationId = request.params()['id']?.toString() ?? '';
    final adminId = request.input('auth_admin_id')?.toString() ?? '';
    final body = request.body;

    await connection!.statement(
      '''
      INSERT INTO admin_notification_cases (
        id, notification_id, status, notes, processed_by, processed_at, created_at, updated_at
      )
      VALUES (\$1, \$2, 'complete', \$3, \$4, NOW(), NOW(), NOW())
      ON CONFLICT (notification_id)
      DO UPDATE SET
        status = 'complete',
        notes = EXCLUDED.notes,
        processed_by = EXCLUDED.processed_by,
        processed_at = NOW(),
        updated_at = NOW()
      ''',
      [
        const Uuid().v4(),
        notificationId,
        body['notes']?.toString() ?? '',
        adminId.isEmpty ? null : adminId,
      ],
    );

    return Response.json({'message': 'Notification processed'}, 200);
  }

  Future<Response> getAdminTransactions(Request request) async {
    final rows = await connection!.select(
      '''
      SELECT t.id, t.reference, t.type, t.amount, t.description, t.created_at,
             t.to_user_id, t.fee_amount, t.context, t.admin_status,
             t.reversed_at, t.reverse_reason,
             u.name AS user_name, tu.name AS transfer_to_name
      FROM bling_transactions t
      LEFT JOIN users u ON u.id = t.user_id
      LEFT JOIN users tu ON tu.id = t.to_user_id
      ORDER BY t.created_at DESC
      LIMIT 100
      ''',
      [],
    );

    return Response.json({
      'transactions': rows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'reference':
                    row['reference']?.toString() ?? row['id']?.toString() ?? '',
                'type': _cleanString(row['type']),
                'amount': _toInt(row['amount']),
                'description': _cleanString(row['description']),
                'created_at': row['created_at']?.toString() ?? '',
                'to_user_id': _cleanString(row['to_user_id']),
                'fee_amount': _toInt(row['fee_amount']),
                'context': _cleanString(row['context']),
                'status':
                    _cleanString(row['admin_status'], fallback: 'complete'),
                'user_full_name':
                    _cleanString(row['user_name'], fallback: 'Bling User'),
                'transfer_to': _cleanString(row['transfer_to_name']),
                'reversed_at': row['reversed_at']?.toString() ?? '',
                'reverse_reason': _cleanString(row['reverse_reason']),
              })
          .toList(),
    }, 200);
  }

  Future<Response> resolveTransaction(Request request, [dynamic _]) async {
    final transactionId = request.params()['id']?.toString() ?? '';
    await connection!.statement(
      '''
      UPDATE bling_transactions
      SET admin_status = 'complete', updated_at = NOW()
      WHERE id = \$1
      ''',
      [transactionId],
    );
    return Response.json({'message': 'Transaction resolved'}, 200);
  }

  Future<Response> reverseTransaction(Request request, [dynamic _]) async {
    final transactionId = request.params()['id']?.toString() ?? '';
    final adminId = request.input('auth_admin_id')?.toString() ?? '';
    final body = request.body;

    await connection!.statement(
      '''
      UPDATE bling_transactions
      SET admin_status = 'reversed',
          reversed_by = \$2,
          reversed_at = NOW(),
          reverse_reason = \$3
      WHERE id = \$1
      ''',
      [
        transactionId,
        adminId.isEmpty ? null : adminId,
        body['reason']?.toString() ?? '',
      ],
    );
    return Response.json({'message': 'Transaction marked as reversed'}, 200);
  }

  Future<List<Map<String, dynamic>>> _fetchLeaderboardUsers(
    String metric,
    int limit,
  ) async {
    final sortExpression = _leaderboardSortExpression(metric);
    final rows = await connection!.select(
      '''
      SELECT u.id, u.name, u.username, u.avatar,
             COALESCE(w.balance, 0) AS bling_balance,
             $sortExpression AS metric_value
      FROM users u
      LEFT JOIN wallets w ON w.user_id = u.id
      LEFT JOIN (
        SELECT user_id, COUNT(*) AS connection_count
        FROM (
          SELECT follower_id AS user_id FROM follows
          UNION ALL
          SELECT following_id AS user_id FROM follows
        ) connection_rows
        GROUP BY user_id
      ) connection_stats ON connection_stats.user_id = u.id
      LEFT JOIN (
        SELECT follower_id AS user_id, COUNT(*) AS invite_count
        FROM follows
        GROUP BY follower_id
      ) invite_stats ON invite_stats.user_id = u.id
      WHERE u.deleted_at IS NULL
      ORDER BY $sortExpression DESC, COALESCE(w.balance, 0) DESC, u.created_at ASC
      LIMIT $limit
      ''',
      [],
    );

    return rows
        .asMap()
        .entries
        .map((entry) => {
              'rank': entry.key + 1,
              'id': entry.value['id']?.toString() ?? '',
              'name': _cleanString(entry.value['name']),
              'username': _cleanString(entry.value['username']),
              'avatar': _cleanString(entry.value['avatar']),
              'bling_balance': _toInt(entry.value['bling_balance']),
              'metric_value': _toInt(entry.value['metric_value']),
            })
        .toList();
  }

  String _leaderboardSortExpression(String metric) {
    switch (_normalizeLeaderboardMetric(metric)) {
      case 'connections':
        return 'COALESCE(connection_stats.connection_count, 0)';
      case 'friend_invites':
        return 'COALESCE(invite_stats.invite_count, 0)';
      case 'bling':
      default:
        return 'COALESCE(w.balance, 0)';
    }
  }

  String _normalizeLeaderboardMetric(String metric) {
    final value = metric.toLowerCase().trim();
    if (value == 'connections') return value;
    if (value == 'friend_invites') return value;
    return 'bling';
  }

  Future<List<Map<String, dynamic>>> _loadLevels() async {
    final levelRows = await connection!.select(
      '''
      SELECT id, level_number, name, required_bling, status, created_at
      FROM admin_levels
      WHERE status = 'active'
      ORDER BY level_number ASC, required_bling ASC
      ''',
      [],
    );

    final medalRows = await connection!.select(
      '''
      SELECT id, level_id, name, metric_label, image_url, sort_order
      FROM admin_level_medals
      WHERE status = 'active'
      ORDER BY sort_order ASC, created_at ASC
      ''',
      [],
    );

    final medalsByLevel = <String, List<Map<String, dynamic>>>{};
    for (final row in medalRows) {
      final levelId = row['level_id']?.toString() ?? '';
      medalsByLevel.putIfAbsent(levelId, () => []).add({
        'id': row['id']?.toString() ?? '',
        'name': row['name']?.toString() ?? '',
        'metric_label': row['metric_label']?.toString() ?? '',
        'image_url': row['image_url']?.toString() ?? '',
        'sort_order': _toInt(row['sort_order']),
      });
    }

    final levels = <Map<String, dynamic>>[];
    for (var index = 0; index < levelRows.length; index++) {
      final row = levelRows[index];
      final requiredBling = _toInt(row['required_bling']);
      final currentThreshold = requiredBling;
      final nextThreshold = index + 1 < levelRows.length
          ? _toInt(levelRows[index + 1]['required_bling'])
          : null;
      final userCountRows = await connection!.select(
        '''
        SELECT COUNT(*) AS count
        FROM users u
        LEFT JOIN wallets w ON w.user_id = u.id
        WHERE u.deleted_at IS NULL
          AND COALESCE(w.balance, 0) >= \$1
          ${nextThreshold == null ? '' : 'AND COALESCE(w.balance, 0) < \$2'}
        ''',
        nextThreshold == null
            ? [currentThreshold]
            : [currentThreshold, nextThreshold],
      );

      levels.add({
        'id': row['id']?.toString() ?? '',
        'level_number': _toInt(row['level_number']),
        'name': _cleanString(row['name']),
        'required_bling': requiredBling,
        'range_start': currentThreshold,
        'range_end': nextThreshold == null ? null : nextThreshold - 1,
        'user_count': _toInt(userCountRows.first['count']),
        'status': _cleanString(row['status'], fallback: 'active'),
        'medals': medalsByLevel[row['id']?.toString() ?? ''] ??
            <Map<String, dynamic>>[],
      });
    }

    return levels;
  }

  Future<List<Map<String, dynamic>>> _fetchLevelUsers(
    int minBling,
    int? maxBling,
  ) async {
    final rows = await connection!.select(
      '''
      SELECT u.id, u.name, u.username, u.avatar, COALESCE(w.balance, 0) AS bling_balance
      FROM users u
      LEFT JOIN wallets w ON w.user_id = u.id
      WHERE u.deleted_at IS NULL
        AND COALESCE(w.balance, 0) >= \$1
        ${maxBling == null ? '' : 'AND COALESCE(w.balance, 0) <= \$2'}
      ORDER BY COALESCE(w.balance, 0) DESC, u.created_at ASC
      LIMIT 20
      ''',
      maxBling == null ? [minBling] : [minBling, maxBling],
    );

    return rows
        .asMap()
        .entries
        .map((entry) => {
              'rank': entry.key + 1,
              'id': entry.value['id']?.toString() ?? '',
              'name': _cleanString(entry.value['name']),
              'username': _cleanString(entry.value['username']),
              'avatar': _cleanString(entry.value['avatar']),
              'bling_balance': _toInt(entry.value['bling_balance']),
            })
        .toList();
  }

  Future<void> _replaceLevelMedals(
    String levelId,
    List<Map<String, dynamic>> medals,
    String adminId,
  ) async {
    await connection!.statement(
      'DELETE FROM admin_level_medals WHERE level_id = \$1',
      [levelId],
    );

    for (var index = 0; index < medals.length; index++) {
      final medal = medals[index];
      await connection!.statement(
        '''
        INSERT INTO admin_level_medals (
          id, level_id, name, metric_label, image_url, sort_order, status, created_by, created_at, updated_at
        )
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 'active', \$7, NOW(), NOW())
        ''',
        [
          const Uuid().v4(),
          levelId,
          medal['name']?.toString() ?? 'Medal',
          medal['metric_label']?.toString() ?? '',
          medal['image_url']?.toString() ?? '',
          index,
          adminId.isEmpty ? null : adminId,
        ],
      );
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  List<String> _decodeStringList(dynamic value) {
    final decoded = jsonDecode(value?.toString() ?? '[]');
    if (decoded is List) {
      return decoded.map((item) => item.toString()).toList();
    }
    return [];
  }

  List<String> _decodeMaybeJsonArray(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return _decodeStringList(value);
  }

  String _slugify(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return normalized.isEmpty ? 'admin' : normalized;
  }

  String _cleanString(dynamic value, {String fallback = ''}) {
    final next = value?.toString().trim() ?? '';
    return next.isEmpty ? fallback : next;
  }
}

final AdminController adminController = AdminController();
