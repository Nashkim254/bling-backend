import 'dart:async';
import 'dart:io';

import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/posts.dart';
import 'package:bling/app/models/reposts_model.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/services/fcm_service.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class RepostsController extends Controller {
  Future<Response> createRepost(Request request) async {
    final authUserId = request.input('auth_user_id')?.toString() ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    Map<String, dynamic> body = Map<String, dynamic>.from(request.body);
    final postId = body['post_id']?.toString() ?? '';
    final now = DateTime.now().toIso8601String();
    body['created_at'] = now;
    body['updated_at'] = now;

    try {
      await RepostsModel().query().insert(body);

      if (postId.isNotEmpty) {
        final post = await Posts().query().where('id', '=', postId).first();
        final ownerId = post?['user_id'] as String?;
        if (ownerId != null && ownerId != authUserId) {
          final reposter = await User().query().where('id', '=', authUserId).first();
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
      }

      return Response.json({'message': 'Repost created successfully'}, HttpStatus.ok);
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

    return Response.json(
        {'message': 'Malformed request: userId is required'},
        HttpStatus.unprocessableEntity);
  }
}

final RepostsController repostsController = RepostsController();
