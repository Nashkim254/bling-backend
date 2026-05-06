import 'dart:convert';
import 'dart:io';

import 'package:bling/app/http/request_data.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:bling/app/models/block_model.dart';
import 'package:bling/app/models/follow.dart';
import 'package:bling/app/models/posts.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class AuthController extends Controller {
  static const int verificationBadgeCost = 1500;

  /// POST /api/register
  Future<Response> register(Request request) async {
    final data = RequestData(request);
    final errors = data.require({
      'name': 'Name is required',
      'username': 'Username is required',
      'password': 'Password is required',
      'email': 'Email is required',
    });
    if (errors.isNotEmpty) {
      return Response.json(errors, HttpStatus.unprocessableEntity);
    }

    final email = data.trimmed('email');
    final username = data.lower('username');
    final password = data.string('password');
    final name = data.trimmed('name');
    final msisdn = data.trimmed('msisdn');
    final avatar = data.trimmed('avatar');

    final emailParts = email.split('@');
    final emailLooksValid = emailParts.length == 2 &&
        emailParts.first.trim().isNotEmpty &&
        emailParts.last.trim().isNotEmpty &&
        emailParts.last.contains('.') &&
        !emailParts.last.startsWith('.') &&
        !emailParts.last.endsWith('.');
    if (!emailLooksValid) {
      return Response.json(
        {'email': 'Invalid email format'},
        HttpStatus.unprocessableEntity,
      );
    }

    final existingEmail =
        await User().query().where('email', '=', email).first();
    if (existingEmail != null) {
      return Response.json({'message': 'Email already in use'}, 409);
    }

    final existingUsername =
        await User().query().where('username', '=', username).first();
    if (existingUsername != null) {
      return Response.json({'message': 'Username already taken'}, 409);
    }

    final userId = const Uuid().v4();
    final hashedPass = Hash().make(password);
    final now = DateTime.now().toIso8601String();

    await User().query().insert({
      'id': userId,
      'name': name,
      'username': username,
      'email': email,
      'msisdn': msisdn,
      'password': hashedPass,
      'avatar': avatar,
      'cover_image': '',
      'bio': '',
      'social_links': '[]',
      'account_type': 'public',
      'bling_score': 0,
      'is_verified': 0,
      'created_at': now,
      'updated_at': now,
    });

    // Create wallet for the new user
    final walletId = const Uuid().v4();
    await Wallet().query().insert({
      'id': walletId,
      'user_id': userId,
      'balance': 0,
      'created_at': now,
      'updated_at': now,
    });

    return Response.json({'message': 'User registered successfully'}, 201);
  }

  /// POST /api/login
  Future<Response> login(Request request) async {
    final data = RequestData(request);
    print('[LOGIN] headers=${request.headers}');
    print('[LOGIN] input_email=${request.input('email')}');
    print('[LOGIN] input_password=${request.input('password')}');
    print('[LOGIN] body=${request.body}');
    final errors = data.require({
      'password': 'Password is required',
      'email': 'Email or username is required',
    });
    if (errors.isNotEmpty) {
      return Response.json(errors, HttpStatus.unprocessableEntity);
    }

    final emailOrUsername = data.trimmed('email');
    final password = data.string('password');

    // Allow login with email OR username
    var user =
        await User().query().where('email', '=', emailOrUsername).first();
    user ??=
        await User().query().where('username', '=', emailOrUsername).first();

    if (user == null) {
      return Response.json({'message': 'Invalid credentials'}, 401);
    }

    if (!Hash().verify(password, user['password'])) {
      return Response.json({'message': 'Invalid credentials'}, 401);
    }

    // Reject permanently deleted accounts
    final status = user['status']?.toString() ?? 'active';
    if (status == 'deleted') {
      return Response.json({'message': 'This account has been deleted'}, 403);
    }

    // Re-enable disabled account on successful login
    if (status == 'disabled') {
      await User().query().where('id', '=', user['id']).update({
        'status': 'active',
        'updated_at': DateTime.now().toIso8601String(),
      });
    }

    String accessToken = '';
    String refreshToken = '';
    try {
      final auth = Auth().login(user);
      user['created_at'] = user['created_at'].toIso8601String();
      user['updated_at'] = user['updated_at'].toIso8601String();
      final token = await auth.createToken(
        expiresIn: const Duration(hours: 24),
        withRefreshToken: true,
      );
      accessToken = token['access_token'];
      refreshToken = token['refresh_token'];
    } catch (e) {
      return Response.json(
          {'message': 'Error creating session: ${e.toString()}'}, 500);
    }

    // Fetch wallet balance
    final wallet =
        await Wallet().query().where('user_id', '=', user['id']).first();
    final blingBalance = wallet?['balance'] ?? 0;

    return Response.json({
      'token': accessToken,
      'refresh_token': refreshToken,
      'expiry': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      'user': {
        'id': user['id']?.toString(),
        'name': user['name']?.toString(),
        'username': user['username']?.toString(),
        'email': user['email']?.toString(),
        'avatar': user['avatar']?.toString(),
        'cover_image': user['cover_image']?.toString(),
        'bio': user['bio']?.toString(),
        'social_links': _decodeSocialLinks(user['social_links']),
        'account_type': user['account_type']?.toString(),
        'bling_score': user['bling_score'],
        'is_verified': user['is_verified'],
        'bling_balance': blingBalance,
      },
    }, HttpStatus.ok);
  }

  /// POST /api/auth/refresh
  Future<Response> refreshToken(Request request) async {
    final data = RequestData(request);
    final refreshTokenValue = data.trimmed('refresh_token');
    if (refreshTokenValue.isEmpty) {
      return Response.json({'message': 'Refresh token required'}, 400);
    }

    try {
      // Validate the refresh token (it's a JWT signed with the same secret)
      await Auth().check(refreshTokenValue, isCustomToken: true);
      final userId = Auth().id()?.toString() ?? '';
      if (userId.isEmpty) {
        return Response.json({'message': 'Invalid refresh token'}, 401);
      }

      final user = await User().query().where('id', '=', userId).first();
      if (user == null) {
        return Response.json({'message': 'User not found'}, 401);
      }

      user['created_at'] = user['created_at'].toIso8601String();
      user['updated_at'] = user['updated_at'].toIso8601String();

      final auth = Auth().login(user);
      final token = await auth.createToken(
        expiresIn: const Duration(hours: 24),
        withRefreshToken: true,
      );

      return Response.json({
        'token': token['access_token'],
        'refresh_token': token['refresh_token'],
        'expiry':
            DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      }, HttpStatus.ok);
    } on JWTExpiredException {
      return Response.json(
          {'message': 'Refresh token expired, please login again'}, 401);
    } catch (e) {
      return Response.json({'message': 'Invalid refresh token'}, 401);
    }
  }

  /// GET /api/user/profile  (authenticated)
  Future<Response> getProfile(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final user = await User().query().where('id', '=', userId).first();
    if (user == null) {
      return Response.json({'message': 'User not found'}, 404);
    }

    final wallet = await Wallet().query().where('user_id', '=', userId).first();
    final blingBalance = wallet?['balance'] ?? 0;

    // Count followers and following using ORM
    final followersCount =
        await Follow().query().where('following_id', '=', userId).count();
    final followingCount =
        await Follow().query().where('follower_id', '=', userId).count();
    final postsCount = await Posts()
        .query()
        .where('user_id', '=', userId)
        .where('is_active', '=', 1)
        .count();

    // Global rank = users with higher bling_score + 1
    final userScore = (user['bling_score'] as num?)?.toInt() ?? 0;
    final rankRows = await connection!.select(
      'SELECT COUNT(*) as cnt FROM users WHERE bling_score > \$1 AND deleted_at IS NULL',
      [userScore],
    );
    final globalRank = ((rankRows.first['cnt'] as num?)?.toInt() ?? 0) + 1;
    final medals = await _loadUserMedals(userId);
    final customization = await _loadUserCustomization(userId, user);

    return Response.json({
      'user': {
        'id': user['id'],
        'name': user['name'],
        'username': user['username'],
        'email': user['email'],
        'avatar': user['avatar'],
        'cover_image': user['cover_image'],
        'bio': user['bio'],
        'social_links': _decodeSocialLinks(user['social_links']),
        'account_type': user['account_type'],
        'bling_score': userScore,
        'is_verified': user['is_verified'],
        'bling_balance': blingBalance,
        'followers_count': followersCount,
        'following_count': followingCount,
        'posts_count': postsCount,
        'global_rank': globalRank,
        'medals': medals,
        ...customization,
        'created_at': user['created_at'].toString(),
      }
    }, HttpStatus.ok);
  }

  Future<Response> purchaseVerificationBadge(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final user = await User().query().where('id', '=', userId).first();
    if (user == null) {
      return Response.json({'message': 'User not found'}, 404);
    }
    if (user['is_verified'] == 1 || user['is_verified'] == true) {
      return Response.json({'message': 'User is already verified'}, 409);
    }

    var wallet = await Wallet().query().where('user_id', '=', userId).first();
    if (wallet == null) {
      final now = DateTime.now().toIso8601String();
      final walletId = const Uuid().v4();
      await Wallet().query().insert({
        'id': walletId,
        'user_id': userId,
        'balance': 0,
        'created_at': now,
        'updated_at': now,
      });
      wallet = {'id': walletId, 'user_id': userId, 'balance': 0};
    }

    final currentBalance = (wallet['balance'] as num?)?.toInt() ?? 0;
    if (currentBalance < verificationBadgeCost) {
      return Response.json({
        'message':
            'Not enough Bling to purchase verification. You need $verificationBadgeCost Bling.',
        'required_bling': verificationBadgeCost,
        'current_balance': currentBalance,
      }, 400);
    }

    final now = DateTime.now().toIso8601String();
    final newBalance = currentBalance - verificationBadgeCost;

    await Wallet().query().where('user_id', '=', userId).update({
      'balance': newBalance,
      'updated_at': now,
    });

    await User().query().where('id', '=', userId).update({
      'is_verified': 1,
      'updated_at': now,
    });

    await connection!.statement(
      '''
      INSERT INTO bling_transactions (id, user_id, to_user_id, type, amount, reference, description, created_at, updated_at)
      VALUES (\$1, \$2, NULL, 'verification_badge', \$3, \$4, \$5, \$6, \$7)
      ''',
      [
        const Uuid().v4(),
        userId,
        verificationBadgeCost,
        'verification_badge_purchase',
        'Purchased verification badge',
        now,
        now,
      ],
    );

    return Response.json({
      'message': 'Verification badge activated',
      'new_balance': newBalance,
      'verification_cost': verificationBadgeCost,
      'is_verified': true,
    }, 200);
  }

  /// PUT /api/user/profile  (authenticated)
  Future<Response> updateProfile(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final requestBody = RequestData(request).body;
    final body = <String, dynamic>{};

    if (requestBody.containsKey('name')) {
      body['name'] = requestBody['name'];
    }
    if (requestBody.containsKey('username')) {
      body['username'] = requestBody['username'];
    }
    if (requestBody.containsKey('bio')) {
      body['bio'] = requestBody['bio'];
    }
    if (requestBody.containsKey('avatar')) {
      body['avatar'] = requestBody['avatar'];
    }
    if (requestBody.containsKey('cover_image')) {
      body['cover_image'] = requestBody['cover_image'];
    }
    if (requestBody.containsKey('account_type')) {
      body['account_type'] = requestBody['account_type'];
    }
    if (requestBody.containsKey('msisdn')) {
      body['msisdn'] = requestBody['msisdn'];
    } else if (requestBody.containsKey('phone')) {
      body['msisdn'] = requestBody['phone'];
    }
    if (requestBody.containsKey('social_links')) {
      body['social_links'] =
          jsonEncode(_normalizeSocialLinks(requestBody['social_links']));
    }

    body['updated_at'] = DateTime.now().toIso8601String();

    await User().query().where('id', '=', userId).update(body);

    return Response.json({'message': 'Profile updated successfully'}, 200);
  }

  /// GET /api/users/:id
  Future<Response> getUserById(Request request, [dynamic _]) async {
    final userId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    final user = await User()
        .query()
        .where('id', '=', userId)
        .where('status', '!=', 'deleted')
        .first();
    if (user == null) {
      return Response.json({'message': 'User not found'}, 404);
    }

    // Check if auth user follows this user
    bool isFollowing = false;
    bool isBlocked = false;
    bool isBlockedBy = false;
    if (authUserId.isNotEmpty) {
      final follow = await Follow()
          .query()
          .where('follower_id', '=', authUserId)
          .where('following_id', '=', userId)
          .first();
      isFollowing = follow != null;

      final blocked = await BlockModel()
          .query()
          .where('user_id', '=', authUserId)
          .where('blocked_user_id', '=', userId)
          .first();
      isBlocked = blocked != null;

      final blockedBy = await BlockModel()
          .query()
          .where('user_id', '=', userId)
          .where('blocked_user_id', '=', authUserId)
          .first();
      isBlockedBy = blockedBy != null;
    }

    final followersCount =
        await Follow().query().where('following_id', '=', userId).count();
    final followingCount =
        await Follow().query().where('follower_id', '=', userId).count();
    final postsCount = await Posts()
        .query()
        .where('user_id', '=', userId)
        .where('is_active', '=', 1)
        .count();
    final userScore = (user['bling_score'] as num?)?.toInt() ?? 0;
    final rankRows = await connection!.select(
      'SELECT COUNT(*) as cnt FROM users WHERE bling_score > \$1 AND deleted_at IS NULL',
      [userScore],
    );
    final globalRank = ((rankRows.first['cnt'] as num?)?.toInt() ?? 0) + 1;
    final medals = await _loadUserMedals(userId);
    final customization = await _loadUserCustomization(userId, user);

    return Response.json({
      'user': {
        'id': user['id'],
        'name': user['name'],
        'username': user['username'],
        'avatar': user['avatar'],
        'cover_image': user['cover_image'],
        'bio': user['bio'],
        'social_links': _decodeSocialLinks(user['social_links']),
        'bling_score': userScore,
        'is_verified': user['is_verified'],
        'is_following': isFollowing,
        'is_blocked': isBlocked,
        'is_blocked_by': isBlockedBy,
        'followers_count': followersCount,
        'following_count': followingCount,
        'posts_count': postsCount,
        'global_rank': globalRank,
        'medals': medals,
        ...customization,
        'created_at': user['created_at'].toString(),
      }
    }, HttpStatus.ok);
  }

  Future<List<Map<String, dynamic>>> _loadUserMedals(String userId) async {
    final medalRows = await connection!.select(
      '''
      SELECT m.id, m.name, m.metric_label, m.image_url, umi.purchased_at
      FROM user_medal_inventory umi
      INNER JOIN admin_level_medals m ON m.id = umi.medal_id
      WHERE umi.user_id = \$1
      ORDER BY umi.purchased_at DESC, m.sort_order ASC
      ''',
      [userId],
    );

    return medalRows
        .map((row) => {
              'id': row['id']?.toString() ?? '',
              'name': row['name']?.toString() ?? '',
              'description': row['metric_label']?.toString() ?? '',
              'image_url': row['image_url']?.toString() ?? '',
              'purchased_at': row['purchased_at']?.toString() ?? '',
            })
        .toList();
  }

  Future<Map<String, dynamic>> _loadUserCustomization(
    String userId,
    Map<String, dynamic> user,
  ) async {
    final equippedAvatarId = user['equipped_avatar_id']?.toString() ?? '';
    final equippedOutfitId = user['equipped_outfit_id']?.toString() ?? '';
    final equippedAccessoryId = user['equipped_accessory_id']?.toString() ?? '';

    final avatarRows = equippedAvatarId.isEmpty
        ? const <Map<String, dynamic>>[]
        : await connection!.select(
            'SELECT image_url FROM avatar_resources WHERE id = \$1 LIMIT 1',
            [equippedAvatarId],
          );
    final outfitRows = equippedOutfitId.isEmpty
        ? const <Map<String, dynamic>>[]
        : await connection!.select(
            'SELECT image_url FROM avatar_accessories WHERE id = \$1 LIMIT 1',
            [equippedOutfitId],
          );
    final accessoryRows = equippedAccessoryId.isEmpty
        ? const <Map<String, dynamic>>[]
        : await connection!.select(
            'SELECT image_url FROM avatar_accessories WHERE id = \$1 LIMIT 1',
            [equippedAccessoryId],
          );
    final equippedLayers = await connection!.select(
      '''
      SELECT aa.id, aa.category, aa.slot, aa.layer_order, aa.scale, aa.offset_x, aa.offset_y, aa.rotation, aa.name, aa.image_url
      FROM user_accessory_inventory uai
      INNER JOIN avatar_accessories aa ON aa.id = uai.accessory_id
      WHERE uai.user_id = \$1
        AND uai.is_equipped = 1
        AND aa.status = 'active'
      ORDER BY aa.layer_order ASC, aa.created_at ASC
      ''',
      [userId],
    );

    return {
      'equipped_avatar_id': equippedAvatarId,
      'equipped_outfit_id': equippedOutfitId,
      'equipped_accessory_id': equippedAccessoryId,
      'equipped_avatar_url': avatarRows.isNotEmpty
          ? avatarRows.first['image_url']?.toString() ?? ''
          : '',
      'equipped_outfit_url': outfitRows.isNotEmpty
          ? outfitRows.first['image_url']?.toString() ?? ''
          : '',
      'equipped_accessory_url': accessoryRows.isNotEmpty
          ? accessoryRows.first['image_url']?.toString() ?? ''
          : '',
      'equipped_layers': equippedLayers
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'category': row['category']?.toString().trim() ?? 'accessory',
                'slot': _normalizeAccessorySlot(
                  row['slot'],
                  fallbackCategory: row['category'],
                ),
                'layer_order':
                    int.tryParse(row['layer_order']?.toString() ?? '0') ?? 0,
                'scale': _resolveAccessoryScale(row),
                'offset_x': _resolveAccessoryOffsetX(row),
                'offset_y': _resolveAccessoryOffsetY(row),
                'rotation': _toDouble(row['rotation']),
                'name': row['name']?.toString().trim() ?? '',
                'image_url': row['image_url']?.toString().trim() ?? '',
              })
          .toList(),
    };
  }

  List<Map<String, String>> _decodeSocialLinks(dynamic value) {
    if (value == null) return [];
    dynamic decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        return [];
      }
    }
    if (decoded is! List) return [];

    return decoded
        .map<Map<String, String>?>((item) {
          if (item is! Map) return null;
          final platform =
              item['platform']?.toString().trim().toLowerCase() ?? '';
          final url = item['url']?.toString().trim() ?? '';
          if (platform.isEmpty || url.isEmpty) return null;
          return {'platform': platform, 'url': url};
        })
        .whereType<Map<String, String>>()
        .toList();
  }

  List<Map<String, String>> _normalizeSocialLinks(dynamic input) {
    const allowed = {
      'instagram': ['instagram.com'],
      'tiktok': ['tiktok.com'],
      'x': ['x.com', 'twitter.com'],
      'reddit': ['reddit.com'],
      'spotify': ['spotify.com', 'open.spotify.com'],
      'facebook': ['facebook.com', 'fb.com'],
      'youtube': ['youtube.com', 'youtu.be'],
    };
    dynamic decoded = input;
    if (input is String) {
      try {
        decoded = jsonDecode(input);
      } catch (_) {
        return [];
      }
    }
    if (decoded is! List) return [];

    return decoded
        .map<Map<String, String>?>((item) {
          if (item is! Map) return null;
          final platform =
              item['platform']?.toString().trim().toLowerCase() ?? '';
          final url = item['url']?.toString().trim() ?? '';
          if (!allowed.containsKey(platform) || url.isEmpty) return null;
          final parsed =
              Uri.tryParse(url.contains('://') ? url : 'https://$url');
          final host = parsed?.host.toLowerCase() ?? '';
          final isValidHost = allowed[platform]!
              .any((domain) => host == domain || host.endsWith('.$domain'));
          if (!isValidHost) return null;
          return {'platform': platform, 'url': url};
        })
        .whereType<Map<String, String>>()
        .toList();
  }

  String _normalizeAccessorySlot(dynamic value, {dynamic fallbackCategory}) {
    final slot = value?.toString().trim().toLowerCase() ?? '';
    if (slot.isNotEmpty) return slot;
    final category = fallbackCategory?.toString().trim().toLowerCase() ?? '';
    return category == 'outfit' ? 'outfit' : 'accessory_main';
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _resolveAccessoryScale(Map<String, dynamic> row) {
    final explicit = _toDouble(row['scale']);
    if (explicit > 0) return explicit;
    return _defaultScaleForSlot(
      _normalizeAccessorySlot(row['slot'], fallbackCategory: row['category']),
    );
  }

  double _resolveAccessoryOffsetX(Map<String, dynamic> row) {
    final explicit = _toDouble(row['offset_x']);
    if (explicit != 0) return explicit;
    return _defaultOffsetXForSlot(
      _normalizeAccessorySlot(row['slot'], fallbackCategory: row['category']),
    );
  }

  double _resolveAccessoryOffsetY(Map<String, dynamic> row) {
    final explicit = _toDouble(row['offset_y']);
    if (explicit != 0) return explicit;
    return _defaultOffsetYForSlot(
      _normalizeAccessorySlot(row['slot'], fallbackCategory: row['category']),
    );
  }

  double _defaultScaleForSlot(String slot) {
    if (slot == 'outfit' || slot == 'torso' || slot == 'shirt') return 0.9;
    if (slot == 'waist' ||
        slot == 'pants' ||
        slot == 'legs' ||
        slot == 'legwear') {
      return 0.8;
    }
    if (slot == 'shoe' ||
        slot == 'shoes' ||
        slot == 'foot' ||
        slot == 'feet' ||
        slot == 'ankle') {
      return 0.56;
    }
    if (slot == 'watch' ||
        slot == 'left_wrist' ||
        slot == 'right_wrist' ||
        slot == 'wrist' ||
        slot == 'bracelet') {
      return 0.24;
    }
    if (slot == 'hand' ||
        slot == 'hands' ||
        slot == 'prop' ||
        slot == 'left_hand' ||
        slot == 'right_hand') {
      return 0.34;
    }
    if (slot == 'glasses' ||
        slot == 'eyes' ||
        slot == 'eye' ||
        slot == 'mask' ||
        slot == 'face') {
      return 0.36;
    }
    if (slot == 'hair' ||
        slot == 'hat' ||
        slot == 'head' ||
        slot == 'head_top') {
      return 0.54;
    }
    if (slot == 'neck' || slot == 'chain' || slot == 'necklace') return 0.28;
    return 0.78;
  }

  double _defaultOffsetXForSlot(String slot) {
    if (slot == 'watch' ||
        slot == 'right_wrist' ||
        slot == 'wrist' ||
        slot == 'bracelet' ||
        slot == 'hand' ||
        slot == 'prop' ||
        slot == 'right_hand') {
      return 0.17;
    }
    if (slot == 'left_wrist' || slot == 'left_hand') return -0.17;
    return 0;
  }

  double _defaultOffsetYForSlot(String slot) {
    if (slot == 'hair' ||
        slot == 'hat' ||
        slot == 'head' ||
        slot == 'head_top') {
      return -0.10;
    }
    if (slot == 'glasses' ||
        slot == 'eyes' ||
        slot == 'eye' ||
        slot == 'mask' ||
        slot == 'face') {
      return -0.05;
    }
    if (slot == 'outfit' || slot == 'torso' || slot == 'shirt') return -0.02;
    if (slot == 'waist' ||
        slot == 'pants' ||
        slot == 'legs' ||
        slot == 'legwear') {
      return 0.12;
    }
    if (slot == 'shoe' ||
        slot == 'shoes' ||
        slot == 'foot' ||
        slot == 'feet' ||
        slot == 'ankle') {
      return 0.24;
    }
    if (slot == 'watch' ||
        slot == 'left_wrist' ||
        slot == 'right_wrist' ||
        slot == 'wrist' ||
        slot == 'bracelet' ||
        slot == 'hand' ||
        slot == 'prop' ||
        slot == 'left_hand' ||
        slot == 'right_hand') {
      return 0.08;
    }
    return 0;
  }

  /// GET /api/users?search=&page=&limit=
  Future<Response> getUsers(Request request) async {
    try {
      final search = (request.input('search') as String? ?? '').trim();
      final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
      final limit =
          int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;
      final authUserId = request.input('auth_user_id') as String? ?? '';

      // Fetch IDs that auth user has blocked or is blocked by
      List<String> excludedIds = [];
      if (authUserId.isNotEmpty) {
        final blockedByMe = await BlockModel()
            .query()
            .select(['blocked_user_id'])
            .where('user_id', '=', authUserId)
            .get();
        final blockedMe = await BlockModel()
            .query()
            .select(['user_id'])
            .where('blocked_user_id', '=', authUserId)
            .get();
        excludedIds = [
          ...(blockedByMe as List)
              .whereType<Map>()
              .map((r) => r['blocked_user_id'].toString()),
          ...(blockedMe as List)
              .whereType<Map>()
              .map((r) => r['user_id'].toString()),
        ];
      }

      var query = User().query().select([
        'id',
        'name',
        'username',
        'avatar',
        'is_verified'
      ]).whereNull('deleted_at');

      if (search.isNotEmpty) {
        query = query.whereRaw(
            '(name ILIKE \'%$search%\' OR username ILIKE \'%$search%\')');
      }

      if (authUserId.isNotEmpty) {
        query = query.where('id', '!=', authUserId);
      }

      for (final id in excludedIds) {
        query = query.where('id', '!=', id);
      }

      final offset = (page - 1) * limit;
      final data =
          await query.orderBy('name', 'ASC').limit(limit).offset(offset).get();

      return Response.json({
        'users': {
          'data': data,
          'page': page,
          'limit': limit,
        }
      }, HttpStatus.ok);
    } catch (e) {
      print('[getUsers] ERROR: $e');
      return Response.json(
          {'message': 'Error fetching users', 'error': e.toString()},
          HttpStatus.internalServerError);
    }
  }

  /// PUT /api/user/fcm-token  (authenticated)
  Future<Response> updateFcmToken(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final token = RequestData(request).trimmed('fcm_token');
    if (token.isEmpty) {
      return Response.json({'message': 'fcm_token required'}, 422);
    }

    await User().query().where('id', '=', userId).update({
      'fcm_token': token,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return Response.json({'message': 'FCM token updated'}, 200);
  }

  /// PUT /api/user/location  (authenticated)
  Future<Response> updateLocation(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty)
      return Response.json({'message': 'Unauthenticated'}, 401);

    final data = RequestData(request);
    final lat = data.doubleValue('latitude');
    final lng = data.doubleValue('longitude');
    if (lat == null || lng == null) {
      return Response.json({'message': 'latitude and longitude required'}, 422);
    }

    await User().query().where('id', '=', userId).update({
      'latitude': lat,
      'longitude': lng,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return Response.json({'message': 'Location updated'}, 200);
  }

  /// POST /api/auth/reset-password  (public)
  /// Body: { email, password }
  /// The OTP must have been verified already (OTP is deleted on verify).
  Future<Response> resetPassword(Request request) async {
    final email =
        (request.input('email')?.toString() ?? '').trim().toLowerCase();
    final password = (request.input('password')?.toString() ?? '').trim();

    if (email.isEmpty || password.isEmpty) {
      return Response.json({'message': 'Email and password are required'}, 422);
    }
    if (password.length < 6) {
      return Response.json(
          {'message': 'Password must be at least 6 characters'}, 422);
    }

    final users = await connection!.select(
      'SELECT id FROM users WHERE email = \$1 AND deleted_at IS NULL LIMIT 1',
      [email],
    );
    if (users.isEmpty) {
      return Response.json(
          {'message': 'No account found with that email'}, 404);
    }

    final hashed = Hash().make(password);
    await User().query().where('email', '=', email).update({
      'password': hashed,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return Response.json({'message': 'Password reset successfully'}, 200);
  }

  /// GET /api/users/nearby?radius=20  (authenticated)
  /// Returns users within [radius] km who have shared their location.
  Future<Response> getNearbyUsers(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty)
      return Response.json({'message': 'Unauthenticated'}, 401);

    final radius =
        double.tryParse(request.input('radius')?.toString() ?? '20') ?? 20.0;

    final me = await User()
        .query()
        .select(['latitude', 'longitude'])
        .where('id', '=', userId)
        .first();

    final myLat = double.tryParse(me?['latitude']?.toString() ?? '');
    final myLng = double.tryParse(me?['longitude']?.toString() ?? '');
    if (myLat == null || myLng == null) {
      return Response.json({'users': []}, 200);
    }

    // Haversine formula in PostgreSQL using the caller's concrete coordinates.
    final rows = await connection!.select("""
      SELECT *
      FROM (
        SELECT
          id,
          name,
          username,
          avatar,
          latitude,
          longitude,
          (
            6371 * acos(
              cos(radians(\$1)) *
              cos(radians(latitude)) *
              cos(radians(longitude) - radians(\$2)) +
              sin(radians(\$1)) *
              sin(radians(latitude))
            )
          ) AS distance_km
        FROM users
        WHERE id != \$3
          AND latitude IS NOT NULL
          AND longitude IS NOT NULL
          AND status = 'active'
      ) nearby
      WHERE distance_km < \$4
      ORDER BY distance_km ASC
      LIMIT 100
    """, [myLat, myLng, userId, radius]);

    return Response.json({'users': rows}, 200);
  }
}

final AuthController authController = AuthController();
