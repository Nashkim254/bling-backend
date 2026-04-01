// ignore_for_file: must_call_super

import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class SeedAdminModule extends Migration {
  static const _defaultAvatar =
      'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=900&q=80';
  static const _defaultAccessory =
      'https://images.unsplash.com/photo-1523170335258-f5ed11844a49?auto=format&fit=crop&w=900&q=80';
  static const _defaultMedal =
      'https://images.unsplash.com/photo-1518546305927-5a555bb7020d?auto=format&fit=crop&w=900&q=80';

  @override
  Future<void> up() async {
    super.up();

    final firstAdminRows = await connection!.select(
      'SELECT id FROM users WHERE is_admin = 1 ORDER BY created_at ASC LIMIT 1',
      [],
    );
    final firstAdminId = firstAdminRows.isNotEmpty
        ? firstAdminRows.first['id']?.toString() ?? ''
        : '';
    final createdBy = firstAdminId.isEmpty ? null : firstAdminId;

    final roles = [
      {
        'name': 'Admin Role',
        'description': 'Full administrative access',
        'permissions': jsonEncode([
          'dashboard',
          'blings',
          'groups',
          'transactions',
          'notifications',
          'resources',
          'settings',
        ]),
      },
      {
        'name': 'Blingers manager',
        'description': 'Manage users and moderation flows',
        'permissions': jsonEncode([
          'blings',
          'notifications',
          'resources',
        ]),
      },
    ];

    for (final role in roles) {
      await connection!.statement(
        '''
        INSERT INTO admin_roles (id, name, description, permissions, status, created_by, created_at, updated_at)
        SELECT
          CAST(\$1 AS CHAR(36)),
          CAST(\$2 AS VARCHAR(120)),
          CAST(\$3 AS TEXT),
          CAST(\$4 AS TEXT),
          'active',
          CAST(\$5 AS CHAR(36)),
          NOW(),
          NOW()
        WHERE NOT EXISTS (
          SELECT 1 FROM admin_roles WHERE LOWER(name) = LOWER(CAST(\$2 AS TEXT))
        )
        ''',
        [
          const Uuid().v4(),
          role['name'],
          role['description'],
          role['permissions'],
          createdBy,
        ],
      );
    }

    if (firstAdminId.isNotEmpty) {
      final roleRows = await connection!.select(
        'SELECT id FROM admin_roles WHERE LOWER(name) = LOWER(\$1) LIMIT 1',
        ['Admin Role'],
      );
      if (roleRows.isNotEmpty) {
        await connection!.statement(
        '''
        INSERT INTO admin_user_roles (id, user_id, role_id, created_at, updated_at)
        SELECT \$1, \$2, \$3, NOW(), NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM admin_user_roles WHERE user_id = \$2 AND role_id = \$3
          )
          ''',
          [const Uuid().v4(), firstAdminId, roleRows.first['id']],
        );
      }
    }

    final avatarCountRows = await connection!.select(
      'SELECT COUNT(*) AS cnt FROM avatar_resources',
      [],
    );
    final avatarCount = (avatarCountRows.first['cnt'] as num?)?.toInt() ?? 0;

    if (avatarCount == 0) {
      final starterAvatars = [
        {'name': 'Avatar 1', 'price': 0, 'owners': 15},
        {'name': 'Avatar 2', 'price': 0, 'owners': 12},
        {'name': 'Avatar 3', 'price': 300, 'owners': 15},
      ];

      for (final avatar in starterAvatars) {
        final avatarId = const Uuid().v4();
        await connection!.statement(
          '''
          INSERT INTO avatar_resources (id, name, image_url, price_bling, is_paid, owners_count, eligible_blingers, status, created_by, created_at, updated_at)
          VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 'All / above level 2 etc', 'active', \$7, NOW(), NOW())
          ''',
          [
            avatarId,
            avatar['name'],
            _defaultAvatar,
            avatar['price'],
            (avatar['price'] as int) > 0 ? 1 : 0,
            avatar['owners'],
            createdBy,
          ],
        );

        for (final accessory in [
          {'name': 'Watch', 'price': 50},
          {'name': 'Glasses', 'price': 50},
        ]) {
          await connection!.statement(
            '''
            INSERT INTO avatar_accessories (id, avatar_id, name, image_url, price_bling, is_paid, owners_count, eligible_blingers, status, created_by, created_at, updated_at)
            VALUES (\$1, \$2, \$3, \$4, \$5, 1, 15, 'All / above level 2 etc', 'active', \$6, NOW(), NOW())
            ''',
            [
              const Uuid().v4(),
              avatarId,
              accessory['name'],
              _defaultAccessory,
              accessory['price'],
              createdBy,
            ],
          );
        }
      }
    }

    final leaderboardCountRows = await connection!.select(
      'SELECT COUNT(*) AS cnt FROM admin_leaderboards',
      [],
    );
    final leaderboardCount =
        (leaderboardCountRows.first['cnt'] as num?)?.toInt() ?? 0;

    if (leaderboardCount == 0) {
      for (final item in const [
        {'name': 'Global Leaderboard', 'metric': 'bling', 'users_limit': 20},
        {'name': "Today's Leaderboard", 'metric': 'connections', 'users_limit': 20},
        {'name': "This Week's Leaderboard", 'metric': 'friend_invites', 'users_limit': 20},
        {'name': 'All Time Leaderboard', 'metric': 'bling', 'users_limit': 50},
      ]) {
        await connection!.statement(
          '''
          INSERT INTO admin_leaderboards (
            id, name, metric, users_limit, status, created_by, created_at, updated_at
          )
          VALUES (\$1, \$2, \$3, \$4, 'active', \$5, NOW(), NOW())
          ''',
          [
            const Uuid().v4(),
            item['name'],
            item['metric'],
            item['users_limit'],
            createdBy,
          ],
        );
      }
    }

    final levelCountRows = await connection!.select(
      'SELECT COUNT(*) AS cnt FROM admin_levels',
      [],
    );
    final levelCount = (levelCountRows.first['cnt'] as num?)?.toInt() ?? 0;

    if (levelCount == 0) {
      final levels = [
        {
          'name': 'Level 0',
          'required_bling': 0,
          'medals': <Map<String, dynamic>>[],
        },
        {
          'name': 'Level 1',
          'required_bling': 500,
          'medals': [
            {'name': 'First Spark', 'metric_label': '*1 purchase'},
          ],
        },
        {
          'name': 'Level 2',
          'required_bling': 1000,
          'medals': [
            {'name': 'Bronze Blossom', 'metric_label': '*3 purchases'},
            {'name': 'Elite Excellence', 'metric_label': '*5 purchases'},
          ],
        },
      ];

      for (var index = 0; index < levels.length; index++) {
        final level = levels[index];
        final levelId = const Uuid().v4();
        await connection!.statement(
          '''
          INSERT INTO admin_levels (
            id, level_number, name, required_bling, status, created_by, created_at, updated_at
          )
          VALUES (\$1, \$2, \$3, \$4, 'active', \$5, NOW(), NOW())
          ''',
          [
            levelId,
            index,
            level['name'],
            level['required_bling'],
            createdBy,
          ],
        );

        final medals = level['medals'] as List<Map<String, dynamic>>;
        for (var medalIndex = 0; medalIndex < medals.length; medalIndex++) {
          final medal = medals[medalIndex];
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
              medal['name'],
              medal['metric_label'],
              _defaultMedal,
              medalIndex,
              createdBy,
            ],
          );
        }
      }
    }
  }

  @override
  Future<void> down() async {}
}
