import 'dart:io';

import 'package:bling/app/models/likes_model.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/posts.dart';
import 'package:bling/app/models/user.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class PostsController extends Controller {
  /// GET /api/feed?page=&limit=  (authenticated)
  /// Returns global feed interleaved with ads every 5 posts
  Future<Response> getFeed(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '10') ?? 10;

    try {
      final posts = await Posts()
          .query()
          .select([
            'posts.id',
            'posts.user_id',
            'posts.caption',
            'posts.post_type',
            'posts.image_url',
            'posts.is_active',
            'posts.created_at',
            'users.name as user_name',
            'users.username as user_username',
            'users.avatar as user_avatar',
            'users.is_verified as user_is_verified',
          ])
          .selectRaw(
              'COALESCE(COUNT(DISTINCT comments.id), 0) AS comment_count, '
              'COALESCE(COUNT(DISTINCT likes.id), 0) AS like_count, '
              'MAX(posts.hashtags::TEXT) AS extracted_hashtags')
          .leftJoin('users', 'users.id', '=', 'posts.user_id')
          .leftJoin('comments', 'comments.post_id', '=', 'posts.id')
          .leftJoin('likes', 'likes.post_id', '=', 'posts.id')
          .where('posts.is_active', '=', 1)
          .groupBy([
            'posts.id',
            'posts.user_id',
            'posts.caption',
            'posts.post_type',
            'posts.image_url',
            'posts.is_active',
            'posts.created_at',
            'users.name',
            'users.username',
            'users.avatar',
            'users.is_verified',
          ])
          .orderBy('posts.created_at', 'DESC')
          .paginate(limit, page);

      // Check which posts the auth user has liked
      List<String> likedPostIds = [];
      if (authUserId.isNotEmpty) {
        final liked =
            await LikesModel().query().where('user_id', '=', authUserId).get();
        likedPostIds =
            (liked as List).map((l) => l['post_id']?.toString() ?? '').toList();
      }

      final data = (posts['data'] as List<dynamic>).map((post) {
        return {
          'id': post['id'],
          'user_id': post['user_id'],
          'user_name': post['user_name'],
          'user_username': post['user_username'],
          'user_avatar': post['user_avatar'],
          'user_is_verified': post['user_is_verified'],
          'caption': post['caption'],
          'post_type': post['post_type']?.trim(),
          'image_url': post['image_url'],
          'is_active': post['is_active'],
          'created_at': post['created_at'].toString(),
          'comment_count': post['comment_count'] ?? 0,
          'like_count': post['like_count'] ?? 0,
          'extracted_hashtags': post['extracted_hashtags'] ?? '[]',
          'is_liked': likedPostIds.contains(post['id']?.toString()),
          'item_type': 'post',
        };
      }).toList();

      return Response.json({
        'feed': {
          'total': posts['total'],
          'per_page': posts['perPage'],
          'page': posts['page'],
          'last_page': posts['lastPage'],
          'next_page': posts['nextPage'],
          'data': data,
        }
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching feed',
        'error': e.toString(),
      }, HttpStatus.internalServerError);
    }
  }

  /// GET /api/posts?userId=&page=&limit=  (user's own posts)
  Future<Response> getPosts(Request request) async {
    final userId = request.input('userId') as String? ?? '';
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '10') ?? 10;
    final authUserId = request.input('auth_user_id') as String? ?? '';

    if (userId.isEmpty) {
      return Response.json(
          {'message': 'userId is required'}, HttpStatus.unprocessableEntity);
    }

    try {
      final posts = await Posts()
          .query()
          .select([
            'posts.id',
            'posts.user_id',
            'posts.caption',
            'posts.post_type',
            'posts.image_url',
            'posts.is_active',
            'posts.created_at',
          ])
          .selectRaw(
              'COALESCE(COUNT(DISTINCT comments.id), 0) AS comment_count, '
              'COALESCE(COUNT(DISTINCT likes.id), 0) AS like_count, '
              'MAX(posts.hashtags::TEXT) AS extracted_hashtags')
          .leftJoin('comments', 'comments.post_id', '=', 'posts.id')
          .leftJoin('likes', 'likes.post_id', '=', 'posts.id')
          .where('posts.user_id', '=', userId)
          .where('posts.is_active', '=', 1)
          .groupBy([
            'posts.id',
            'posts.user_id',
            'posts.caption',
            'posts.post_type',
            'posts.image_url',
            'posts.is_active',
            'posts.created_at',
          ])
          .orderBy('posts.created_at', 'DESC')
          .paginate(limit, page);

      List<String> likedPostIds = [];
      if (authUserId.isNotEmpty) {
        final liked =
            await LikesModel().query().where('user_id', '=', authUserId).get();
        likedPostIds =
            (liked as List).map((l) => l['post_id']?.toString() ?? '').toList();
      }

      final data = (posts['data'] as List<dynamic>).map((post) {
        return {
          'id': post['id'],
          'user_id': post['user_id'],
          'caption': post['caption'],
          'post_type': post['post_type']?.trim(),
          'image_url': post['image_url'],
          'is_active': post['is_active'],
          'created_at': post['created_at'].toString(),
          'comment_count': post['comment_count'] ?? 0,
          'like_count': post['like_count'] ?? 0,
          'extracted_hashtags': post['extracted_hashtags'] ?? '[]',
          'is_liked': likedPostIds.contains(post['id']?.toString()),
        };
      }).toList();

      return Response.json({
        'posts': {
          'total': posts['total'],
          'per_page': posts['perPage'],
          'page': posts['page'],
          'last_page': posts['lastPage'],
          'data': data,
        }
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching posts',
        'error': e.toString(),
      }, HttpStatus.internalServerError);
    }
  }

  /// POST /api/posts  (authenticated)
  Future<Response> createPost(Request request) async {
    request.validate({
      'caption': 'required|string',
      'post_type': 'required|string',
    }, {
      'caption.required': 'Caption is required',
      'post_type.required': 'Post type is required',
    });

    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    try {
      final body = Map<String, dynamic>.from(request.body);
      body.remove('auth_user_id');
      final postId = const Uuid().v4();
      final now = DateTime.now().toIso8601String();

      body['id'] = postId;
      body['user_id'] = authUserId;
      body['is_active'] = 1;
      body['created_at'] = now;
      body['updated_at'] = now;

      // Handle hashtags - extract from caption if not provided
      if (body['hashtags'] == null) {
        final caption = body['caption'] as String? ?? '';
        final hashtags =
            RegExp(r'#\w+').allMatches(caption).map((m) => m.group(0)).toList();
        body['hashtags'] = hashtags;
      }

      await Posts().query().insert(body);

      // Increment user bling_score for posting
      await User().query().where('id', '=', authUserId).update({
        'bling_score': await _getNewScore(authUserId, 10),
        'updated_at': now,
      });

      return Response.json({
        'message': 'Post created successfully',
        'post_id': postId,
      }, 201);
    } catch (e) {
      return Response.json({
        'message': 'Error creating post',
        'error': e.toString(),
      }, HttpStatus.internalServerError);
    }
  }

  /// DELETE /api/posts/:id  (authenticated, own post only)
  Future<Response> deletePost(Request request) async {
    final postId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final post = await Posts().query().where('id', '=', postId).first();
    if (post == null) {
      return Response.json({'message': 'Post not found'}, 404);
    }
    if (post['user_id'] != authUserId) {
      return Response.json({'message': 'Forbidden'}, 403);
    }

    await Posts().query().where('id', '=', postId).update({
      'is_active': 0,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return Response.json({'message': 'Post deleted'}, 200);
  }

  /// POST /api/posts/:id/like  (authenticated) - toggle like
  Future<Response> toggleLike(Request request) async {
    final postId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final post = await Posts().query().where('id', '=', postId).first();
    if (post == null) {
      return Response.json({'message': 'Post not found'}, 404);
    }

    final existingLike = await LikesModel()
        .query()
        .where('user_id', '=', authUserId)
        .where('post_id', '=', postId)
        .first();

    final now = DateTime.now().toIso8601String();

    if (existingLike != null) {
      // Unlike
      await LikesModel()
          .query()
          .where('user_id', '=', authUserId)
          .where('post_id', '=', postId)
          .delete();
      return Response.json({'message': 'Post unliked', 'liked': false}, 200);
    } else {
      // Like
      await LikesModel().query().insert({
        'id': const Uuid().v4(),
        'user_id': authUserId,
        'post_id': postId,
        'created_at': now,
        'updated_at': now,
      });

      // Create notification for post owner (if not self-like)
      if (post['user_id'] != authUserId) {
        final liker = await User().query().where('id', '=', authUserId).first();
        await NotificationModel().query().insert({
          'id': const Uuid().v4(),
          'user_id': post['user_id'],
          'type': 'like',
          'title': 'New Like',
          'body': '${liker?['name'] ?? 'Someone'} liked your post',
          'data': '{"post_id":"$postId","user_id":"$authUserId"}',
          'is_read': 0,
          'created_at': now,
          'updated_at': now,
        });
      }

      return Response.json({'message': 'Post liked', 'liked': true}, 200);
    }
  }

  /// POST /api/posts/:id/comment  (authenticated)
  Future<Response> addComment(Request request) async {
    request.validate({
      'content': 'required|string',
    }, {
      'content.required': 'Comment content is required',
    });

    final postId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final post = await Posts().query().where('id', '=', postId).first();
    if (post == null) {
      return Response.json({'message': 'Post not found'}, 404);
    }

    final now = DateTime.now().toIso8601String();
    final commentId = const Uuid().v4();

    await connection!.statement(
      'INSERT INTO comments (id, user_id, post_id, content, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6)',
      [commentId, authUserId, postId, request.body['content'], now, now],
    );

    // Notify post owner
    if (post['user_id'] != authUserId) {
      final commenter =
          await User().query().where('id', '=', authUserId).first();
      await NotificationModel().query().insert({
        'id': const Uuid().v4(),
        'user_id': post['user_id'],
        'type': 'comment',
        'title': 'New Comment',
        'body': '${commenter?['name'] ?? 'Someone'} commented on your post',
        'data': '{"post_id":"$postId","user_id":"$authUserId"}',
        'is_read': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    return Response.json({
      'message': 'Comment added',
      'comment_id': commentId,
    }, 201);
  }

  /// GET /api/posts/:id/comments
  Future<Response> getComments(Request request) async {
    final postId = request.params()['id'] as String? ?? '';
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;

    try {
      final comments = await connection!.select(
        '''SELECT c.id, c.content, c.created_at,
           u.id as user_id, u.name as user_name, u.username, u.avatar
           FROM comments c
           JOIN users u ON u.id = c.user_id
           WHERE c.post_id = \$1
           ORDER BY c.created_at ASC
           LIMIT \$2 OFFSET \$3''',
        [postId, limit, (page - 1) * limit],
      );

      return Response.json({
        'comments': comments
            .map((c) => {
                  'id': c['id'],
                  'content': c['content'],
                  'user_id': c['user_id'],
                  'user_name': c['user_name'],
                  'username': c['username'],
                  'user_avatar': c['avatar'],
                  'created_at': c['created_at'].toString(),
                })
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching comments',
        'error': e.toString(),
      }, 500);
    }
  }

  Future<int> _getNewScore(String userId, int increment) async {
    final user = await User().query().where('id', '=', userId).first();
    final currentScore = (user?['bling_score'] as int?) ?? 0;
    return currentScore + increment;
  }
}

final PostsController postsController = PostsController();
