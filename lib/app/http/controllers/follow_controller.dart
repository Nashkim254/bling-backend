import 'dart:io';

import 'package:bling/app/models/follow.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/user.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class FollowController extends Controller {
  /// POST /api/follow/:userId  (authenticated)
  Future<Response> follow(Request request) async {
    final followingId = request.params()['userId'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }
    if (followingId == authUserId) {
      return Response.json({'message': 'Cannot follow yourself'}, 400);
    }

    final target = await User().query().where('id', '=', followingId).first();
    if (target == null) {
      return Response.json({'message': 'User not found'}, 404);
    }

    final existing = await Follow()
        .query()
        .where('follower_id', '=', authUserId)
        .where('following_id', '=', followingId)
        .first();

    if (existing != null) {
      return Response.json(
          {'message': 'Already following', 'is_following': true}, 200);
    }

    final now = DateTime.now().toIso8601String();
    await Follow().query().insert({
      'id': const Uuid().v4(),
      'follower_id': authUserId,
      'following_id': followingId,
      'created_at': now,
    });

    // Notify the followed user
    final follower = await User().query().where('id', '=', authUserId).first();
    await NotificationModel().query().insert({
      'id': const Uuid().v4(),
      'user_id': followingId,
      'type': 'follow',
      'title': 'New Follower',
      'body': '${follower?['name'] ?? 'Someone'} started following you',
      'data': '{"user_id":"$authUserId"}',
      'is_read': 0,
      'created_at': now,
      'updated_at': now,
    });

    return Response.json(
        {'message': 'Followed successfully', 'is_following': true}, 201);
  }

  /// DELETE /api/follow/:userId  (authenticated)
  Future<Response> unfollow(Request request) async {
    final followingId = request.params()['userId'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    await Follow()
        .query()
        .where('follower_id', '=', authUserId)
        .where('following_id', '=', followingId)
        .delete();

    return Response.json(
        {'message': 'Unfollowed successfully', 'is_following': false}, 200);
  }

  /// GET /api/user/followers?page=&limit=  (authenticated)
  Future<Response> getFollowers(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;

    try {
      final followers = await connection!.select(
        '''SELECT u.id, u.name, u.username, u.avatar, u.is_verified, u.bling_score,
           f.created_at as followed_at
           FROM follows f
           JOIN users u ON u.id = f.follower_id
           WHERE f.following_id = \$1
           ORDER BY f.created_at DESC
           LIMIT \$2 OFFSET \$3''',
        [authUserId, limit, (page - 1) * limit],
      );

      return Response.json({
        'followers': followers
            .map((u) => {
                  'id': u['id'],
                  'name': u['name'],
                  'username': u['username'],
                  'avatar': u['avatar'],
                  'is_verified': u['is_verified'],
                  'bling_score': u['bling_score'],
                  'followed_at': u['followed_at'].toString(),
                })
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// GET /api/user/following?page=&limit=  (authenticated)
  Future<Response> getFollowing(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;

    try {
      final following = await connection!.select(
        '''SELECT u.id, u.name, u.username, u.avatar, u.is_verified, u.bling_score,
           f.created_at as followed_at
           FROM follows f
           JOIN users u ON u.id = f.following_id
           WHERE f.follower_id = \$1
           ORDER BY f.created_at DESC
           LIMIT \$2 OFFSET \$3''',
        [authUserId, limit, (page - 1) * limit],
      );

      return Response.json({
        'following': following
            .map((u) => {
                  'id': u['id'],
                  'name': u['name'],
                  'username': u['username'],
                  'avatar': u['avatar'],
                  'is_verified': u['is_verified'],
                  'bling_score': u['bling_score'],
                  'followed_at': u['followed_at'].toString(),
                })
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }
}

final FollowController followController = FollowController();
