import 'dart:io';

import 'package:bling/app/models/block_model.dart';
import 'package:bling/app/models/follow.dart';
import 'package:bling/app/models/posts.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class AuthController extends Controller {
  /// POST /api/register
  Future<Response> register(Request request) async {
    request.validate({
      'name': 'required|string',
      'username': 'required|string',
      'password': 'required|string',
      'email': 'required|email',
    }, {
      'name.required': 'Name is required',
      'username.required': 'Username is required',
      'password.required': 'Password is required',
      'email.required': 'Email is required',
      'email.email': 'Invalid email format',
    });

    final body = request.body;
    final email = body['email'] as String;
    final username = (body['username'] as String).toLowerCase().trim();
    final password = body['password'] as String;

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
      'name': body['name'],
      'username': username,
      'email': email,
      'msisdn': body['msisdn'] ?? '',
      'password': hashedPass,
      'avatar': body['avatar'] ?? '',
      'cover_image': '',
      'bio': '',
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
    request.validate({
      'password': 'required|string',
      'email': 'required|string',
    }, {
      'password.required': 'Password is required',
      'email.required': 'Email or username is required',
    });

    final body = request.body;
    final emailOrUsername = body['email'] as String;
    final password = body['password'] as String;

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
        'id': user['id'],
        'name': user['name'],
        'username': user['username'],
        'email': user['email'],
        'avatar': user['avatar'],
        'cover_image': user['cover_image'],
        'bio': user['bio'],
        'account_type': user['account_type'],
        'bling_score': user['bling_score'],
        'is_verified': user['is_verified'],
        'bling_balance': blingBalance,
      },
    }, HttpStatus.ok);
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

    return Response.json({
      'user': {
        'id': user['id'],
        'name': user['name'],
        'username': user['username'],
        'email': user['email'],
        'avatar': user['avatar'],
        'cover_image': user['cover_image'],
        'bio': user['bio'],
        'account_type': user['account_type'],
        'bling_score': userScore,
        'is_verified': user['is_verified'],
        'bling_balance': blingBalance,
        'followers_count': followersCount,
        'following_count': followingCount,
        'posts_count': postsCount,
        'global_rank': globalRank,
        'created_at': user['created_at'].toString(),
      }
    }, HttpStatus.ok);
  }

  /// PUT /api/user/profile  (authenticated)
  Future<Response> updateProfile(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final body = Map<String, dynamic>.from(request.body);
    // Remove fields that shouldn't be updated directly
    body.remove('id');
    body.remove('password');
    body.remove('email');
    body.remove('auth_user_id');
    body['updated_at'] = DateTime.now().toIso8601String();

    await User().query().where('id', '=', userId).update(body);

    return Response.json({'message': 'Profile updated successfully'}, 200);
  }

  /// GET /api/users/:id
  Future<Response> getUserById(Request request) async {
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

    return Response.json({
      'user': {
        'id': user['id'],
        'name': user['name'],
        'username': user['username'],
        'avatar': user['avatar'],
        'cover_image': user['cover_image'],
        'bio': user['bio'],
        'bling_score': userScore,
        'is_verified': user['is_verified'],
        'is_following': isFollowing,
        'is_blocked': isBlocked,
        'is_blocked_by': isBlockedBy,
        'followers_count': followersCount,
        'following_count': followingCount,
        'posts_count': postsCount,
        'global_rank': globalRank,
        'created_at': user['created_at'].toString(),
      }
    }, HttpStatus.ok);
  }

  /// GET /api/users?search=&page=&limit=
  Future<Response> getUsers(Request request) async {
    final search = request.input('search') as String? ?? '';
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
        ...(blockedByMe as List).map((r) => r['blocked_user_id'].toString()),
        ...(blockedMe as List).map((r) => r['user_id'].toString()),
      ];
    }

    var query = User().query().select([
      'id',
      'name',
      'username',
      'avatar',
      'bling_score',
      'is_verified'
    ]).where('status', '=', 'active');

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

    final result =
        await query.orderBy('bling_score', 'DESC').paginate(limit, page);

    return Response.json({'users': result}, HttpStatus.ok);
  }

  /// PUT /api/user/fcm-token  (authenticated)
  Future<Response> updateFcmToken(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final token = request.body['fcm_token']?.toString() ?? '';
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
    if (userId.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final lat = double.tryParse(request.body['latitude']?.toString() ?? '');
    final lng = double.tryParse(request.body['longitude']?.toString() ?? '');
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

  /// GET /api/users/nearby?radius=20  (authenticated)
  /// Returns users within [radius] km who have shared their location.
  Future<Response> getNearbyUsers(Request request) async {
    final userId = request.input('auth_user_id') as String? ?? '';
    if (userId.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final radius = double.tryParse(request.input('radius')?.toString() ?? '20') ?? 20.0;

    // Haversine formula in PostgreSQL
    final rows = await connection!.select("""
      SELECT id, name, username, avatar, latitude, longitude,
        (6371 * acos(
          cos(radians((SELECT latitude FROM users WHERE id = \$1))) *
          cos(radians(latitude)) *
          cos(radians(longitude) - radians((SELECT longitude FROM users WHERE id = \$1))) +
          sin(radians((SELECT latitude FROM users WHERE id = \$1))) *
          sin(radians(latitude))
        )) AS distance_km
      FROM users
      WHERE id != \$1
        AND latitude IS NOT NULL
        AND longitude IS NOT NULL
        AND status = 'active'
      HAVING (6371 * acos(
          cos(radians((SELECT latitude FROM users WHERE id = \$1))) *
          cos(radians(latitude)) *
          cos(radians(longitude) - radians((SELECT longitude FROM users WHERE id = \$1))) +
          sin(radians((SELECT latitude FROM users WHERE id = \$1))) *
          sin(radians(latitude))
        )) < \$2
      ORDER BY distance_km ASC
      LIMIT 100
    """, [userId, radius]);

    return Response.json({'users': rows}, 200);
  }

}

final AuthController authController = AuthController();
