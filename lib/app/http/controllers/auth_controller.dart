import 'dart:io';

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
        'bling_score': user['bling_score'],
        'is_verified': user['is_verified'],
        'bling_balance': blingBalance,
        'followers_count': followersCount,
        'following_count': followingCount,
        'posts_count': postsCount,
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

    final user = await User().query().where('id', '=', userId).first();
    if (user == null) {
      return Response.json({'message': 'User not found'}, 404);
    }

    // Check if auth user follows this user
    bool isFollowing = false;
    if (authUserId.isNotEmpty) {
      final follow = await Follow()
          .query()
          .where('follower_id', '=', authUserId)
          .where('following_id', '=', userId)
          .first();
      isFollowing = follow != null;
    }

    return Response.json({
      'user': {
        'id': user['id'],
        'name': user['name'],
        'username': user['username'],
        'avatar': user['avatar'],
        'cover_image': user['cover_image'],
        'bio': user['bio'],
        'bling_score': user['bling_score'],
        'is_verified': user['is_verified'],
        'is_following': isFollowing,
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

    var query = User().query().select(
        ['id', 'name', 'username', 'avatar', 'bling_score', 'is_verified']);

    if (search.isNotEmpty) {
      query = query.whereRaw(
          '(name ILIKE \'%$search%\' OR username ILIKE \'%$search%\')');
    }

    if (authUserId.isNotEmpty) {
      query = query.where('id', '!=', authUserId);
    }

    final result =
        await query.orderBy('bling_score', 'DESC').paginate(limit, page);

    return Response.json({'users': result}, HttpStatus.ok);
  }
}

final AuthController authController = AuthController();
