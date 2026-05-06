import 'dart:convert';
import 'dart:io';
import 'package:vania/vania.dart';
import 'package:uuid/uuid.dart';

/// Run with: dart run lib/database/seeds/seed.dart
void main() async {
  await MigrationConnection().setup();
  await Seeder().run();
  await MigrationConnection().closeConnection();
  exit(0);
}

class Seeder {
  Future<void> run() async {
    await _seedBlingPackages();
    await _seedAds();
    await _seedAdminUsersAndRoles();
    await _seedSampleUsers();
    await _seedGroups();
    await _seedSampleTransactions();
    await _seedSampleNotifications();
    await _seedAdminResources();
    print('Seeding complete.');
  }

  Future<void> _seedBlingPackages() async {
    // Check if already seeded
    final existing = await connection!
        .select('SELECT COUNT(*) as count FROM bling_packages', []);
    if (((existing.first['count'] as num?)?.toInt() ?? 0) > 0) {
      print('Bling packages already seeded, skipping.');
      return;
    }

    final packages = [
      {
        'id': const Uuid().v4(),
        'name': 'Starter',
        'bling_amount': 100,
        'price_cents': 499,
        'store_product_id': 'social.blingsocial.app.starter',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Basic',
        'bling_amount': 250,
        'price_cents': 999,
        'store_product_id': 'social.blingsocial.app.basic',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Popular',
        'bling_amount': 700,
        'price_cents': 2499,
        'store_product_id': 'social.blingsocial.app.popular',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Premium',
        'bling_amount': 1500,
        'price_cents': 4999,
        'store_product_id': 'social.blingsocial.app.premium',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Elite',
        'bling_amount': 4000,
        'price_cents': 9999,
        'store_product_id': 'social.blingsocial.app.elite',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    ];

    for (final pkg in packages) {
      await connection!.statement(
        'INSERT INTO bling_packages (id, name, bling_amount, price_cents, store_product_id, is_active, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8)',
        [
          pkg['id'],
          pkg['name'],
          pkg['bling_amount'],
          pkg['price_cents'],
          pkg['store_product_id'],
          pkg['is_active'],
          pkg['created_at'],
          pkg['updated_at'],
        ],
      );
    }
    print('Bling packages seeded: ${packages.length} packages.');
  }

  Future<void> _seedAds() async {
    final existing =
        await connection!.select('SELECT COUNT(*) as count FROM ads', []);
    if (((existing.first['count'] as num?)?.toInt() ?? 0) > 0) {
      print('Ads already seeded, skipping.');
      return;
    }

    final ads = [
      {
        'id': const Uuid().v4(),
        'title': 'Get Verified on Bling!',
        'body': 'Stand out with a verified badge. Apply now.',
        'image_url': 'https://via.placeholder.com/400x200?text=Bling+Verified',
        'target_url': '',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'title': 'Buy Bling — Climb the Ranks',
        'body': 'Purchase Bling to level up and get featured on leaderboards.',
        'image_url': 'https://via.placeholder.com/400x200?text=Buy+Bling',
        'target_url': '',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'title': 'Join the Weekly Challenge',
        'body': 'Win 5,000 Bling by participating in this week\'s challenge!',
        'image_url': 'https://via.placeholder.com/400x200?text=Challenge',
        'target_url': '',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    ];

    for (final ad in ads) {
      await connection!.statement(
        'INSERT INTO ads (id, title, body, image_url, target_url, is_active, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8)',
        [
          ad['id'],
          ad['title'],
          ad['body'],
          ad['image_url'],
          ad['target_url'],
          ad['is_active'],
          ad['created_at'],
          ad['updated_at'],
        ],
      );
    }
    print('Ads seeded: ${ads.length} ads.');
  }

  Future<void> _seedAdminUsersAndRoles() async {
    final admins = [
      {
        'name': 'Olivia Rhye',
        'username': 'olivia.admin',
        'email': 'olivia@untitledui.com',
        'msisdn': '0712345678',
        'password': 'Admin@12345',
        'role': 'Admin Role',
      },
      {
        'name': 'John Doe',
        'username': 'john.admin',
        'email': 'john.admin@bling.app',
        'msisdn': '0711111111',
        'password': 'Admin@12345',
        'role': 'Blingers manager',
      },
    ];

    final roles = [
      {
        'name': 'Admin Role',
        'description': 'Full administrative access',
        'permissions': [
          'dashboard',
          'blings',
          'groups',
          'transactions',
          'notifications',
          'resources',
          'settings',
        ],
      },
      {
        'name': 'Blingers manager',
        'description': 'Manage users and moderation flows',
        'permissions': ['blings', 'notifications', 'resources'],
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
          NULL,
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
          jsonEncode(role['permissions']),
        ],
      );
    }

    for (final admin in admins) {
      final existing = await connection!.select(
        'SELECT id FROM users WHERE email = \$1 LIMIT 1',
        [admin['email']],
      );

      String userId;
      if (existing.isEmpty) {
        userId = const Uuid().v4();
        await connection!.statement(
          '''
          INSERT INTO users (
            id, name, username, email, msisdn, password, avatar, cover_image, bio,
            account_type, bling_score, is_verified, status, is_admin, created_at, updated_at
          )
          VALUES (
            \$1, \$2, \$3, \$4, \$5, \$6, '', '', '',
            'private', \$7, 1, 'active', 1, NOW(), NOW()
          )
          ''',
          [
            userId,
            admin['name'],
            admin['username'],
            admin['email'],
            admin['msisdn'],
            Hash().make(admin['password']!),
            admin['role'] == 'Admin Role' ? 1500 : 900,
          ],
        );
        await _ensureWallet(
            userId, admin['role'] == 'Admin Role' ? 4200 : 2100);
      } else {
        userId = existing.first['id']?.toString() ?? '';
        await connection!.statement(
          '''
          UPDATE users
          SET is_admin = 1, status = 'active', is_verified = 1, updated_at = NOW()
          WHERE id = \$1
          ''',
          [userId],
        );
        await _ensureWallet(
            userId, admin['role'] == 'Admin Role' ? 4200 : 2100);
      }

      final roleRows = await connection!.select(
        'SELECT id FROM admin_roles WHERE LOWER(name) = LOWER(\$1) LIMIT 1',
        [admin['role']],
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
          [const Uuid().v4(), userId, roleRows.first['id']],
        );
      }
    }

    print('Admin users and roles seeded.');
  }

  Future<void> _seedSampleUsers() async {
    final sampleUsers = [
      ['Peter Piper', 'peter.piper', 'peter@bling.app', 1500],
      ['Jane Doe', 'jane.doe', 'jane@bling.app', 1300],
      ['Michael Early', 'michael.early', 'michael@bling.app', 1100],
      ['James Bond', 'james.bond', 'james@bling.app', 950],
      ['Mary Jane', 'mary.jane', 'mary@bling.app', 875],
      ['John Peter', 'john.peter', 'john.peter@bling.app', 780],
    ];

    for (final sample in sampleUsers) {
      final existing = await connection!.select(
        'SELECT id FROM users WHERE email = \$1 LIMIT 1',
        [sample[2]],
      );

      if (existing.isNotEmpty) {
        await _ensureWallet(
            existing.first['id']?.toString() ?? '', sample[3] as int);
        continue;
      }

      final userId = const Uuid().v4();
      await connection!.statement(
        '''
        INSERT INTO users (
          id, name, username, email, msisdn, password, avatar, cover_image, bio,
          account_type, bling_score, is_verified, status, is_admin, created_at, updated_at
        )
        VALUES (
          \$1, \$2, \$3, \$4, '', \$5, '', '', '',
          'public', \$6, 0, 'active', 0, NOW(), NOW()
        )
        ''',
        [
          userId,
          sample[0],
          sample[1],
          sample[2],
          Hash().make('User@12345'),
          sample[3],
        ],
      );
      await _ensureWallet(userId, sample[3] as int);
    }

    print('Sample users seeded.');
  }

  Future<void> _seedGroups() async {
    final existing = await connection!.select(
      'SELECT COUNT(*) as count FROM groups',
      [],
    );
    if (((existing.first['count'] as num?)?.toInt() ?? 0) > 0) {
      print('Groups already seeded, skipping.');
      return;
    }

    final creatorRows = await connection!.select(
      'SELECT id FROM users WHERE is_admin = 1 ORDER BY created_at ASC LIMIT 1',
      [],
    );
    final memberRows = await connection!.select(
      'SELECT id FROM users WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 8',
      [],
    );

    if (creatorRows.isEmpty || memberRows.length < 3) {
      print('Not enough users to seed groups, skipping.');
      return;
    }

    final creatorId = creatorRows.first['id']?.toString() ?? '';
    final now = DateTime.now();
    final groups = [
      {
        'name': 'Great Blingers',
        'description':
            'Luxury creators and ambitious blingers sharing wins, ideas, and standout moments.',
        'required_level': 0,
        'medals_count': 4,
      },
      {
        'name': 'Above Level 5 Circle',
        'description':
            'A focused group for users above level 5 to connect, collaborate, and flex premium milestones.',
        'required_level': 5,
        'medals_count': 3,
      },
      {
        'name': 'Founders Lounge',
        'description':
            'Operators, founders, and serious builders discussing growth, money, and influence.',
        'required_level': 2,
        'medals_count': 2,
      },
    ];

    for (var index = 0; index < groups.length; index++) {
      final groupId = const Uuid().v4();
      final conversationId = const Uuid().v4();
      final createdAt = now.subtract(Duration(days: index)).toIso8601String();
      final group = groups[index];

      await connection!.statement(
        '''
        INSERT INTO conversations (id, type, name, avatar, created_by, created_at, updated_at)
        VALUES (\$1, 'group', \$2, '', \$3, \$4, \$4)
        ''',
        [conversationId, group['name'], creatorId, createdAt],
      );

      await connection!.statement(
        '''
        INSERT INTO groups
          (id, name, description, avatar, cover_image, required_level, medals_count,
           visibility, is_active, created_by, conversation_id, created_at, updated_at)
        VALUES
          (\$1, \$2, \$3, '', '', \$4, \$5, 'public', 1, \$6, \$7, \$8, \$8)
        ''',
        [
          groupId,
          group['name'],
          group['description'],
          group['required_level'],
          group['medals_count'],
          creatorId,
          conversationId,
          createdAt,
        ],
      );

      final selectedMembers = memberRows.take(4 + index).toList();
      for (var memberIndex = 0;
          memberIndex < selectedMembers.length;
          memberIndex++) {
        final memberId = selectedMembers[memberIndex]['id']?.toString() ?? '';
        final memberRole = memberId == creatorId ? 'admin' : 'member';
        final joinedAt = now
            .subtract(Duration(days: index, minutes: memberIndex * 3))
            .toIso8601String();

        await connection!.statement(
          '''
          INSERT INTO group_members
            (id, group_id, user_id, role, status, joined_at, created_at, updated_at)
          VALUES (\$1, \$2, \$3, \$4, 'active', \$5, \$5, \$5)
          ''',
          [const Uuid().v4(), groupId, memberId, memberRole, joinedAt],
        );

        await connection!.statement(
          '''
          INSERT INTO conversation_members
            (id, conversation_id, user_id, role, joined_at, created_at, updated_at)
          VALUES (\$1, \$2, \$3, \$4, \$5, \$5, \$5)
          ''',
          [const Uuid().v4(), conversationId, memberId, memberRole, joinedAt],
        );
      }
    }

    print('Groups seeded.');
  }

  Future<void> _seedSampleTransactions() async {
    final existing = await connection!.select(
      'SELECT COUNT(*) as count FROM bling_transactions',
      [],
    );
    if (((existing.first['count'] as num?)?.toInt() ?? 0) > 20) {
      print('Sample transactions already seeded, skipping.');
      return;
    }

    final users = await connection!.select(
      'SELECT id, name FROM users ORDER BY created_at ASC LIMIT 6',
      [],
    );
    if (users.length < 3) return;

    final now = DateTime.now();
    final rows = [
      {
        'user_id': users[0]['id'],
        'to_user_id': null,
        'type': 'purchase',
        'amount': 400,
        'reference': 'TR2345678900',
        'description': 'Purchased Starter package',
        'admin_status': 'complete',
      },
      {
        'user_id': users[1]['id'],
        'to_user_id': users[2]['id'],
        'type': 'transfer_out',
        'amount': 400,
        'reference': 'TR2345678901',
        'description': 'Sent to ${users[2]['name']}',
        'admin_status': 'pending',
      },
      {
        'user_id': users[2]['id'],
        'to_user_id': users[1]['id'],
        'type': 'transfer_in',
        'amount': 400,
        'reference': 'TR2345678902',
        'description': 'Received from ${users[1]['name']}',
        'admin_status': 'complete',
      },
    ];

    for (var i = 0; i < rows.length; i++) {
      await connection!.statement(
        '''
        INSERT INTO bling_transactions (
          id, user_id, to_user_id, type, amount, reference, description,
          created_at, updated_at, admin_status, fee_amount, context, reverse_reason
        )
        SELECT \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$8, \$9, 0, '', ''
        WHERE NOT EXISTS (
          SELECT 1 FROM bling_transactions WHERE reference = \$6
        )
        ''',
        [
          const Uuid().v4(),
          rows[i]['user_id'],
          rows[i]['to_user_id'],
          rows[i]['type'],
          rows[i]['amount'],
          rows[i]['reference'],
          rows[i]['description'],
          now.subtract(Duration(days: i)).toIso8601String(),
          rows[i]['admin_status'],
        ],
      );
    }

    print('Sample transactions seeded.');
  }

  Future<void> _seedSampleNotifications() async {
    final existing = await connection!.select(
      'SELECT COUNT(*) as count FROM notifications',
      [],
    );
    if (((existing.first['count'] as num?)?.toInt() ?? 0) > 20) {
      print('Sample notifications already seeded, skipping.');
      return;
    }

    final users = await connection!.select(
      'SELECT id, name FROM users ORDER BY created_at ASC LIMIT 4',
      [],
    );
    if (users.isEmpty) return;

    final notifications = [
      {
        'user_id': users[0]['id'],
        'type': 'payment_issue',
        'title': 'Peter Piper',
        'body': 'I have an issue with my payment',
      },
      {
        'user_id': users[1]['id'],
        'type': 'app_malfunction',
        'title': 'Jane Doe',
        'body': 'App Malfunction',
      },
      {
        'user_id': users[2]['id'],
        'type': 'transaction',
        'title': 'Michael Early',
        'body': 'Transaction',
      },
    ];

    for (final item in notifications) {
      final notificationId = const Uuid().v4();
      await connection!.statement(
        '''
        INSERT INTO notifications (id, user_id, type, title, body, data, is_read, created_at, updated_at)
        VALUES (\$1, \$2, \$3, \$4, \$5, '{}', 0, NOW(), NOW())
        ''',
        [
          notificationId,
          item['user_id'],
          item['type'],
          item['title'],
          item['body'],
        ],
      );

      if (item['type'] == 'transaction') {
        await connection!.statement(
          '''
          INSERT INTO admin_notification_cases (
            id, notification_id, status, notes, processed_by, processed_at, created_at, updated_at
          )
          VALUES (\$1, \$2, 'complete', 'Seeded resolved case', NULL, NOW(), NOW(), NOW())
          ON CONFLICT (notification_id) DO NOTHING
          ''',
          [const Uuid().v4(), notificationId],
        );
      }
    }

    print('Sample notifications seeded.');
  }

  Future<void> _seedAdminResources() async {
    final existing = await connection!.select(
      'SELECT COUNT(*) as count FROM avatar_resources',
      [],
    );
    final hasAvatars = ((existing.first['count'] as num?)?.toInt() ?? 0) > 0;

    if (!hasAvatars) {
      final avatars = [
        ['Cool Guy Avatar', 50, 1],
        ['Avatar 1', 0, 0],
        ['Avatar 2', 0, 0],
        ['Avatar 3', 300, 1],
      ];

      for (final avatar in avatars) {
        final avatarId = const Uuid().v4();
        await connection!.statement(
          '''
          INSERT INTO avatar_resources (
            id, name, image_url, price_bling, is_paid, owners_count, eligible_blingers,
            status, created_by, created_at, updated_at
          )
          VALUES (\$1, \$2, \$3, \$4, \$5, 15, 'All / above level 2 etc', 'active', NULL, NOW(), NOW())
          ''',
          [
            avatarId,
            avatar[0],
            'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=900&q=80',
            avatar[1],
            avatar[2],
          ],
        );

        for (final accessory in [
          ['Watch', 50],
          ['Glasses', 50],
        ]) {
          await connection!.statement(
            '''
            INSERT INTO avatar_accessories (
              id, avatar_id, name, image_url, price_bling, is_paid, owners_count, eligible_blingers,
              status, created_by, created_at, updated_at
            )
            VALUES (\$1, \$2, \$3, \$4, \$5, 1, 15, 'All / above level 2 etc', 'active', NULL, NOW(), NOW())
            ''',
            [
              const Uuid().v4(),
              avatarId,
              accessory[0],
              'https://images.unsplash.com/photo-1523170335258-f5ed11844a49?auto=format&fit=crop&w=900&q=80',
              accessory[1],
            ],
          );
        }
      }
    }

    final leaderboardCount = await connection!.select(
      'SELECT COUNT(*) as count FROM admin_leaderboards',
      [],
    );
    if (((leaderboardCount.first['count'] as num?)?.toInt() ?? 0) == 0) {
      for (final item in const [
        {'name': 'Global Leaderboard', 'metric': 'bling', 'users_limit': 20},
        {
          'name': "Today's Leaderboard",
          'metric': 'connections',
          'users_limit': 20
        },
        {
          'name': "This Week's Leaderboard",
          'metric': 'friend_invites',
          'users_limit': 20
        },
        {
          'name': 'January 2024 Leaderboard',
          'metric': 'bling',
          'users_limit': 10
        },
        {'name': 'All Time Leaderboard', 'metric': 'bling', 'users_limit': 50},
      ]) {
        await connection!.statement(
          '''
          INSERT INTO admin_leaderboards (
            id, name, metric, users_limit, status, created_by, created_at, updated_at
          )
          VALUES (\$1, \$2, \$3, \$4, 'active', NULL, NOW(), NOW())
          ''',
          [
            const Uuid().v4(),
            item['name'],
            item['metric'],
            item['users_limit'],
          ],
        );
      }
    }

    final levelCount = await connection!.select(
      'SELECT COUNT(*) as count FROM admin_levels',
      [],
    );
    if (((levelCount.first['count'] as num?)?.toInt() ?? 0) == 0) {
      final levels = [
        {
          'name': 'Level 0',
          'required_bling': 0,
          'medals': <List<dynamic>>[],
        },
        {
          'name': 'Level 1',
          'required_bling': 500,
          'medals': [
            ['First Spark', '*1 purchase'],
          ],
        },
        {
          'name': 'Level 2',
          'required_bling': 1000,
          'medals': [
            ['Bronze Blossom', '*3 purchases'],
            ['Elite Excellence', '*5 purchases'],
          ],
        },
        {
          'name': 'Level 3',
          'required_bling': 5000,
          'medals': [
            ['Silver Presence', '*10 purchases'],
            ['Silver Presence', '*15 purchases'],
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
          VALUES (\$1, \$2, \$3, \$4, 'active', NULL, NOW(), NOW())
          ''',
          [
            levelId,
            index,
            level['name'],
            level['required_bling'],
          ],
        );

        final medals = level['medals'] as List<dynamic>;
        for (var medalIndex = 0; medalIndex < medals.length; medalIndex++) {
          final medal = medals[medalIndex] as List<dynamic>;
          await connection!.statement(
            '''
            INSERT INTO admin_level_medals (
              id, level_id, name, metric_label, image_url, sort_order, status, created_by, created_at, updated_at
            )
            VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 'active', NULL, NOW(), NOW())
            ''',
            [
              const Uuid().v4(),
              levelId,
              medal[0],
              medal[1],
              'https://images.unsplash.com/photo-1518546305927-5a555bb7020d?auto=format&fit=crop&w=900&q=80',
              medalIndex,
            ],
          );
        }
      }
    }

    print('Admin resources seeded.');
  }

  Future<void> _ensureWallet(String userId, int balance) async {
    if (userId.isEmpty) return;
    final existing = await connection!.select(
      'SELECT id FROM wallets WHERE user_id = \$1 LIMIT 1',
      [userId],
    );

    if (existing.isEmpty) {
      await connection!.statement(
        'INSERT INTO wallets (id, user_id, balance, created_at, updated_at) VALUES (\$1,\$2,\$3,NOW(),NOW())',
        [const Uuid().v4(), userId, balance],
      );
    } else {
      await connection!.statement(
        'UPDATE wallets SET balance = \$2, updated_at = NOW() WHERE user_id = \$1',
        [userId, balance],
      );
    }
  }
}
