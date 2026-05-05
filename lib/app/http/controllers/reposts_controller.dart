import 'dart:async';
import 'dart:io';

import 'package:bling/app/http/request_data.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/posts.dart';
import 'package:bling/app/models/reposts_model.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/services/feed_interaction_service.dart';
import 'package:bling/services/fcm_service.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class RepostsController extends Controller {
  Future<Response> createRepost(Request request, [dynamic _]) async {
    final authUserId = request.input('auth_user_id')?.toString() ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final data = RequestData(request);
    final postId = request.params()['id']?.toString().isNotEmpty == true
        ? request.params()['id'].toString()
        : data.trimmed('post_id');
    if (postId.isEmpty) {
      return Response.json({'message': 'Post id is required'}, 422);
    }

    final now = DateTime.now().toIso8601String();

    try {
      final post = await Posts().query().where('id', '=', postId).first();
      if (post == null) {
        return Response.json({'message': 'Post not found'}, 404);
      }

      final existingRepost = await RepostsModel()
          .query()
          .where('user_id', '=', authUserId)
          .where('post_id', '=', postId)
          .first();

      if (existingRepost != null) {
        return Response.json({'message': 'Post already reposted'}, 200);
      }

      await RepostsModel().query().insert({
        'id': const Uuid().v4(),
        'user_id': authUserId,
        'post_id': postId,
        'created_at': now,
        'updated_at': now,
      });
      unawaited(FeedInteractionService.instance.record(
        userId: authUserId,
        postId: postId,
        interactionType: 'repost',
      ));

      final ownerId = post['user_id'] as String?;
      if (ownerId != null && ownerId != authUserId) {
        final reposter =
            await User().query().where('id', '=', authUserId).first();
        final name = reposter?['name'] as String? ?? 'Someone';

        await NotificationModel().query().insert({
          'id': const Uuid().v4(),
          'user_id': ownerId,
          'type': 'repost',
          'title': 'New Repost',
          'body': '$name reposted your post',
          'data': '{"post_id":"$postId","user_id":"$authUserId"}',
          'is_read': 0,
          'created_at': now,
          'updated_at': now,
        });

        unawaited(FcmService.instance.sendToUser(
          ownerId,
          title: 'New Repost',
          body: '$name reposted your post',
          data: {'type': 'repost', 'post_id': postId},
        ));
      }

      return Response.json(
          {'message': 'Repost created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error creating repost'}, 422);
    }
  }

  Future<Response> getReposts(Request request) async {
    String? userId = request.input('userId');
    int page = int.parse(request.input('page') ?? '1');
    int limit = int.parse(request.input('limit') ?? '10');

    if (userId != null && userId.isNotEmpty) {
      try {
        final reposts = await RepostsModel()
            .query()
            .where('user_id', '=', userId)
            .paginate(limit, page);
        return Response.json({'reposts': reposts}, HttpStatus.ok);
      } catch (e) {
        return Response.json({
          'message': 'An error occurred while fetching reposts',
          'error': e.toString(),
        }, HttpStatus.internalServerError);
      }
    }

    return Response.json({'message': 'Malformed request: userId is required'},
        HttpStatus.unprocessableEntity);
  }
}

final RepostsController repostsController = RepostsController();
