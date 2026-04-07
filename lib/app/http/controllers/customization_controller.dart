import 'dart:io';

import 'package:bling/app/models/user.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class CustomizationController extends Controller {
  String _authUserId(Request request) {
    final requestUserId = request.input('auth_user_id')?.toString() ?? '';
    if (requestUserId.isNotEmpty) return requestUserId;
    return Auth().id()?.toString() ?? '';
  }

  Future<Response> getCatalog(Request request) async {
    final userId = _authUserId(request);
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final avatarRows = await connection!.select(
      '''
      SELECT id, name, image_url, price_bling, is_paid, owners_count, eligible_blingers, status
      FROM avatar_resources
      WHERE status = 'active'
      ORDER BY created_at DESC
      ''',
      [],
    );
    final ownedAvatarRows = await connection!.select(
      '''
      SELECT avatar_id, is_equipped
      FROM user_avatar_inventory
      WHERE user_id = \$1
      ''',
      [userId],
    );
    final ownedAvatars = {
      for (final row in ownedAvatarRows) row['avatar_id']?.toString() ?? '': row
    };
    final accessoryRows = await connection!.select(
      '''
      SELECT id, avatar_id, category, name, image_url, price_bling, is_paid, owners_count, eligible_blingers, status
      FROM avatar_accessories
      WHERE status = 'active'
      ORDER BY created_at DESC
      ''',
      [],
    );
    final ownedAccessoryRows = await connection!.select(
      '''
      SELECT accessory_id, is_equipped
      FROM user_accessory_inventory
      WHERE user_id = \$1
      ''',
      [userId],
    );
    final ownedAccessories = {
      for (final row in ownedAccessoryRows)
        row['accessory_id']?.toString() ?? '': row,
    };

    final medalRows = await connection!.select(
      '''
      SELECT m.id,
             m.level_id,
             m.name,
             m.metric_label,
             m.image_url,
             m.sort_order,
             m.price_bling,
             m.is_paid,
             l.level_number,
             l.name AS level_name,
             l.required_bling
      FROM admin_level_medals m
      INNER JOIN admin_levels l ON l.id = m.level_id
      WHERE m.status = 'active' AND l.status = 'active'
      ORDER BY l.level_number ASC, m.sort_order ASC, m.created_at ASC
      ''',
      [],
    );
    final ownedMedalRows = await connection!.select(
      '''
      SELECT medal_id
      FROM user_medal_inventory
      WHERE user_id = \$1
      ''',
      [userId],
    );
    final ownedMedals = ownedMedalRows
        .map((row) => row['medal_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final wallet = await Wallet().query().where('user_id', '=', userId).first();
    final balance = (wallet?['balance'] as num?)?.toInt() ?? 0;
    final user = await User().query().where('id', '=', userId).first();

    return Response.json({
      'wallet_balance': balance,
      'equipped': {
        'avatar_id': user?['equipped_avatar_id']?.toString() ?? '',
        'outfit_id': user?['equipped_outfit_id']?.toString() ?? '',
        'accessory_id': user?['equipped_accessory_id']?.toString() ?? '',
      },
      'avatars': avatarRows.map((row) {
        final owned = ownedAvatars[row['id']?.toString() ?? ''];
        return {
          'id': row['id']?.toString() ?? '',
          'name': row['name']?.toString() ?? '',
          'image_url': row['image_url']?.toString() ?? '',
          'price_bling': _toInt(row['price_bling']),
          'is_paid': _toInt(row['is_paid']) == 1,
          'owners_count': _toInt(row['owners_count']),
          'eligible_blingers': row['eligible_blingers']?.toString() ?? '',
          'owned': owned != null,
          'is_equipped': owned != null && _toInt(owned['is_equipped']) == 1,
        };
      }).toList(),
      'outfits': accessoryRows
          .where((row) =>
              _cleanString(row['category'], fallback: 'accessory') == 'outfit')
          .map((row) => _formatAccessoryRow(row, ownedAccessories))
          .toList(),
      'accessories': accessoryRows
          .where((row) =>
              _cleanString(row['category'], fallback: 'accessory') != 'outfit')
          .map((row) => _formatAccessoryRow(row, ownedAccessories))
          .toList(),
      'medals': medalRows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'level_id': row['level_id']?.toString() ?? '',
                'name': row['name']?.toString() ?? '',
                'metric_label': row['metric_label']?.toString() ?? '',
                'image_url': row['image_url']?.toString() ?? '',
                'sort_order': _toInt(row['sort_order']),
                'price_bling': _toInt(row['price_bling']),
                'is_paid': _toInt(row['is_paid']) == 1,
                'level_number': _toInt(row['level_number']),
                'level_name': row['level_name']?.toString() ?? '',
                'required_bling': _toInt(row['required_bling']),
                'description': _buildMedalDescription(row),
                'unlock_hint': _buildMedalUnlockHint(row),
                'is_level_unlocked': balance >= _toInt(row['required_bling']),
                'owned': ownedMedals.contains(row['id']?.toString() ?? ''),
              })
          .toList(),
    }, HttpStatus.ok);
  }

  Future<Response> purchaseAvatar(Request request, [dynamic _]) async {
    final userId = _authUserId(request);
    final avatarId = request.params()['id']?.toString() ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }
    if (avatarId.isEmpty) {
      return Response.json({'message': 'Avatar not found'}, 404);
    }

    final avatarRows = await connection!.select(
      '''
      SELECT id, image_url, price_bling, is_paid, owners_count
      FROM avatar_resources
      WHERE id = \$1 AND status = 'active'
      LIMIT 1
      ''',
      [avatarId],
    );
    if (avatarRows.isEmpty) {
      return Response.json({'message': 'Avatar not found'}, 404);
    }

    final existing = await connection!.select(
      '''
      SELECT id
      FROM user_avatar_inventory
      WHERE user_id = \$1 AND avatar_id = \$2
      LIMIT 1
      ''',
      [userId, avatarId],
    );
    if (existing.isNotEmpty) {
      return Response.json({'message': 'Avatar already owned'}, 200);
    }

    final avatar = avatarRows.first;
    final cost = _toInt(avatar['price_bling']);
    final isPaid = _toInt(avatar['is_paid']) == 1 && cost > 0;
    if (isPaid) {
      final deductionError = await _deductWallet(
        userId: userId,
        amount: cost,
        type: 'avatar_purchase',
        description: 'Avatar purchase',
        referenceId: avatarId,
      );
      if (deductionError != null) {
        return Response.json({'message': deductionError}, 422);
      }
    }

    await connection!.statement(
      '''
      INSERT INTO user_avatar_inventory (
        id, user_id, avatar_id, is_equipped, purchased_at, created_at, updated_at
      )
      VALUES (\$1, \$2, \$3, 0, NOW(), NOW(), NOW())
      ''',
      [const Uuid().v4(), userId, avatarId],
    );

    await connection!.statement(
      '''
      UPDATE avatar_resources
      SET owners_count = owners_count + 1, updated_at = NOW()
      WHERE id = \$1
      ''',
      [avatarId],
    );

    return Response.json({'message': 'Avatar purchased'}, 201);
  }

  Future<Response> equipAvatar(Request request, [dynamic _]) async {
    final userId = _authUserId(request);
    final avatarId = request.params()['id']?.toString() ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }
    if (avatarId.isEmpty) {
      return Response.json({'message': 'Avatar not found'}, 404);
    }

    final avatarRows = await connection!.select(
      '''
      SELECT id, image_url, price_bling, is_paid
      FROM avatar_resources
      WHERE id = \$1 AND status = 'active'
      LIMIT 1
      ''',
      [avatarId],
    );
    if (avatarRows.isEmpty) {
      return Response.json({'message': 'Avatar not found'}, 404);
    }

    final ownedRows = await connection!.select(
      '''
      SELECT id
      FROM user_avatar_inventory
      WHERE user_id = \$1 AND avatar_id = \$2
      LIMIT 1
      ''',
      [userId, avatarId],
    );
    if (ownedRows.isEmpty) {
      final cost = _toInt(avatarRows.first['price_bling']);
      final isPaid = _toInt(avatarRows.first['is_paid']) == 1 && cost > 0;
      if (isPaid) {
        final deductionError = await _deductWallet(
          userId: userId,
          amount: cost,
          type: 'avatar_purchase',
          description: 'Avatar purchase',
          referenceId: avatarId,
        );
        if (deductionError != null) {
          return Response.json({'message': deductionError}, 422);
        }
      }
      await connection!.statement(
        '''
        INSERT INTO user_avatar_inventory (
          id, user_id, avatar_id, is_equipped, purchased_at, created_at, updated_at
        )
        VALUES (\$1, \$2, \$3, 0, NOW(), NOW(), NOW())
        ''',
        [const Uuid().v4(), userId, avatarId],
      );
      await connection!.statement(
        '''
        UPDATE avatar_resources
        SET owners_count = owners_count + 1, updated_at = NOW()
        WHERE id = \$1
        ''',
        [avatarId],
      );
    }

    await connection!.statement(
      'UPDATE user_avatar_inventory SET is_equipped = 0, updated_at = NOW() WHERE user_id = \$1',
      [userId],
    );
    await connection!.statement(
      '''
      UPDATE user_avatar_inventory
      SET is_equipped = 1, updated_at = NOW()
      WHERE user_id = \$1 AND avatar_id = \$2
      ''',
      [userId, avatarId],
    );

    final imageUrl = avatarRows.first['image_url']?.toString() ?? '';
    await User().query().where('id', '=', userId).update({
      'avatar': imageUrl,
      'equipped_avatar_id': avatarId,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return Response.json({
      'message': 'Avatar equipped',
      'avatar_url': imageUrl,
    }, HttpStatus.ok);
  }

  Future<Response> purchaseMedal(Request request, [dynamic _]) async {
    final userId = _authUserId(request);
    final medalId = request.params()['id']?.toString() ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }
    if (medalId.isEmpty) {
      return Response.json({'message': 'Medal not found'}, 404);
    }

    final medalRows = await connection!.select(
      '''
      SELECT id, name, price_bling, is_paid
      FROM admin_level_medals
      WHERE id = \$1 AND status = 'active'
      LIMIT 1
      ''',
      [medalId],
    );
    if (medalRows.isEmpty) {
      return Response.json({'message': 'Medal not found'}, 404);
    }

    final existing = await connection!.select(
      '''
      SELECT id
      FROM user_medal_inventory
      WHERE user_id = \$1 AND medal_id = \$2
      LIMIT 1
      ''',
      [userId, medalId],
    );
    if (existing.isNotEmpty) {
      return Response.json({'message': 'Medal already owned'}, 200);
    }

    final medal = medalRows.first;
    final cost = _toInt(medal['price_bling']);
    final isPaid = _toInt(medal['is_paid']) == 1 && cost > 0;
    if (isPaid) {
      final deductionError = await _deductWallet(
        userId: userId,
        amount: cost,
        type: 'medal_purchase',
        description: 'Medal purchase',
        referenceId: medalId,
      );
      if (deductionError != null) {
        return Response.json({'message': deductionError}, 422);
      }
    }

    await connection!.statement(
      '''
      INSERT INTO user_medal_inventory (
        id, user_id, medal_id, purchased_at, created_at, updated_at
      )
      VALUES (\$1, \$2, \$3, NOW(), NOW(), NOW())
      ''',
      [const Uuid().v4(), userId, medalId],
    );

    return Response.json({'message': 'Medal purchased'}, 201);
  }

  Future<Response> purchaseAccessory(Request request, [dynamic _]) async {
    final userId = _authUserId(request);
    final accessoryId = request.params()['id']?.toString() ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }
    if (accessoryId.isEmpty) {
      return Response.json({'message': 'Accessory not found'}, 404);
    }

    final rows = await connection!.select(
      '''
      SELECT id, category, image_url, price_bling, is_paid, owners_count
      FROM avatar_accessories
      WHERE id = \$1 AND status = 'active'
      LIMIT 1
      ''',
      [accessoryId],
    );
    if (rows.isEmpty) {
      return Response.json({'message': 'Accessory not found'}, 404);
    }

    final existing = await connection!.select(
      '''
      SELECT id
      FROM user_accessory_inventory
      WHERE user_id = \$1 AND accessory_id = \$2
      LIMIT 1
      ''',
      [userId, accessoryId],
    );
    if (existing.isNotEmpty) {
      return Response.json({'message': 'Accessory already owned'}, 200);
    }

    final accessory = rows.first;
    final cost = _toInt(accessory['price_bling']);
    final isPaid = _toInt(accessory['is_paid']) == 1 && cost > 0;
    if (isPaid) {
      final deductionError = await _deductWallet(
        userId: userId,
        amount: cost,
        type: 'accessory_purchase',
        description: 'Accessory purchase',
        referenceId: accessoryId,
      );
      if (deductionError != null) {
        return Response.json({'message': deductionError}, 422);
      }
    }

    await connection!.statement(
      '''
      INSERT INTO user_accessory_inventory (
        id, user_id, accessory_id, is_equipped, purchased_at, created_at, updated_at
      )
      VALUES (\$1, \$2, \$3, 0, NOW(), NOW(), NOW())
      ''',
      [const Uuid().v4(), userId, accessoryId],
    );

    await connection!.statement(
      '''
      UPDATE avatar_accessories
      SET owners_count = owners_count + 1, updated_at = NOW()
      WHERE id = \$1
      ''',
      [accessoryId],
    );

    return Response.json({'message': 'Accessory purchased'}, 201);
  }

  Future<Response> equipAccessory(Request request, [dynamic _]) async {
    final userId = _authUserId(request);
    final accessoryId = request.params()['id']?.toString() ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }
    if (accessoryId.isEmpty) {
      return Response.json({'message': 'Accessory not found'}, 404);
    }

    final rows = await connection!.select(
      '''
      SELECT id, category, image_url, price_bling, is_paid
      FROM avatar_accessories
      WHERE id = \$1 AND status = 'active'
      LIMIT 1
      ''',
      [accessoryId],
    );
    if (rows.isEmpty) {
      return Response.json({'message': 'Accessory not found'}, 404);
    }

    final accessory = rows.first;
    final category = _cleanString(accessory['category'], fallback: 'accessory');
    final ownedRows = await connection!.select(
      '''
      SELECT id
      FROM user_accessory_inventory
      WHERE user_id = \$1 AND accessory_id = \$2
      LIMIT 1
      ''',
      [userId, accessoryId],
    );
    if (ownedRows.isEmpty) {
      final cost = _toInt(accessory['price_bling']);
      final isPaid = _toInt(accessory['is_paid']) == 1 && cost > 0;
      if (isPaid) {
        final deductionError = await _deductWallet(
          userId: userId,
          amount: cost,
          type: 'accessory_purchase',
          description: 'Accessory purchase',
          referenceId: accessoryId,
        );
        if (deductionError != null) {
          return Response.json({'message': deductionError}, 422);
        }
      }
      await connection!.statement(
        '''
        INSERT INTO user_accessory_inventory (
          id, user_id, accessory_id, is_equipped, purchased_at, created_at, updated_at
        )
        VALUES (\$1, \$2, \$3, 0, NOW(), NOW(), NOW())
        ''',
        [const Uuid().v4(), userId, accessoryId],
      );
      await connection!.statement(
        '''
        UPDATE avatar_accessories
        SET owners_count = owners_count + 1, updated_at = NOW()
        WHERE id = \$1
        ''',
        [accessoryId],
      );
    }

    final resetCategory = category == 'outfit' ? 'outfit' : 'accessory';
    await connection!.statement(
      '''
      UPDATE user_accessory_inventory uai
      SET is_equipped = 0, updated_at = NOW()
      FROM avatar_accessories aa
      WHERE uai.accessory_id = aa.id
        AND uai.user_id = \$1
        AND aa.category = \$2
      ''',
      [userId, resetCategory],
    );
    await connection!.statement(
      '''
      UPDATE user_accessory_inventory
      SET is_equipped = 1, updated_at = NOW()
      WHERE user_id = \$1 AND accessory_id = \$2
      ''',
      [userId, accessoryId],
    );

    await User().query().where('id', '=', userId).update({
      if (category == 'outfit') 'equipped_outfit_id': accessoryId,
      if (category != 'outfit') 'equipped_accessory_id': accessoryId,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return Response.json({
      'message':
          category == 'outfit' ? 'Outfit equipped' : 'Accessory equipped',
      'category': category,
      'image_url': accessory['image_url']?.toString() ?? '',
    }, HttpStatus.ok);
  }

  Future<String?> _deductWallet({
    required String userId,
    required int amount,
    required String type,
    required String description,
    required String referenceId,
  }) async {
    final wallet = await Wallet().query().where('user_id', '=', userId).first();
    if (wallet == null) return 'Wallet not found';

    final balance = (wallet['balance'] as num?)?.toInt() ?? 0;
    if (balance < amount) return 'Not enough Bling';

    await Wallet().query().where('user_id', '=', userId).update({
      'balance': balance - amount,
      'updated_at': DateTime.now().toIso8601String(),
    });

    await connection!.statement(
      '''
      INSERT INTO bling_transactions (
        id, user_id, to_user_id, type, amount, reference, description, created_at, updated_at
      )
      VALUES (\$1, \$2, NULL, \$3, \$4, \$5, \$6, NOW(), NOW())
      ''',
      [
        const Uuid().v4(),
        userId,
        type,
        amount,
        referenceId,
        description,
      ],
    );
    return null;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  Map<String, dynamic> _formatAccessoryRow(
    Map<String, dynamic> row,
    Map<String, dynamic> ownedAccessories,
  ) {
    final owned = ownedAccessories[row['id']?.toString() ?? ''];
    return {
      'id': row['id']?.toString() ?? '',
      'avatar_id': row['avatar_id']?.toString() ?? '',
      'category': _cleanString(row['category'], fallback: 'accessory'),
      'name': row['name']?.toString() ?? '',
      'image_url': row['image_url']?.toString() ?? '',
      'price_bling': _toInt(row['price_bling']),
      'is_paid': _toInt(row['is_paid']) == 1,
      'owners_count': _toInt(row['owners_count']),
      'eligible_blingers': row['eligible_blingers']?.toString() ?? '',
      'owned': owned != null,
      'is_equipped': owned != null && _toInt(owned['is_equipped']) == 1,
    };
  }

  String _buildMedalDescription(Map<String, dynamic> row) {
    final name = row['name']?.toString() ?? 'Medal';
    final metric = row['metric_label']?.toString() ?? '';
    final levelNumber = _toInt(row['level_number']);
    if (metric.isNotEmpty) {
      final prefix = levelNumber > 0 ? 'Level $levelNumber medal. ' : '';
      return '$prefix$name is tied to $metric and helps elevate the profile status of top Blingers.';
    }
    return '$name unlocks extra profile prestige and recognition across Bling.';
  }

  String _buildMedalUnlockHint(Map<String, dynamic> row) {
    final price = _toInt(row['price_bling']);
    final requiredBling = _toInt(row['required_bling']);
    if (price > 0) return 'Buy with $price Bling';
    if (requiredBling > 0) return 'Requires $requiredBling Bling to unlock';
    return 'Claim for free';
  }

  String _cleanString(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

final CustomizationController customizationController =
    CustomizationController();
