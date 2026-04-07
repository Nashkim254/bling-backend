import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bling/app/models/block_model.dart';
import 'package:bling/app/models/likes_model.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/posts.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/services/fcm_service.dart';
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
      // Build block exclusion list for auth user
      final List<String> blockedIds = [];
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
        blockedIds.addAll((blockedByMe as List)
            .whereType<Map>()
            .map((r) => r['blocked_user_id'].toString()));
        blockedIds.addAll((blockedMe as List)
            .whereType<Map>()
            .map((r) => r['user_id'].toString()));
      }

      var postsQuery = Posts()
          .query()
          .select([
            'posts.id',
            'posts.user_id',
            'posts.caption',
            'posts.post_type',
            'posts.image_url',
            'posts.thumbnail_url',
            'posts.video_url',
            'posts.media_kind',
            'posts.storage_bucket',
            'posts.storage_path',
            'posts.mime_type',
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
              "COALESCE(MIN(posts.hashtags::TEXT), '[]') AS extracted_hashtags, "
              "COALESCE(MIN(posts.media::TEXT), '[]') AS media")
          .leftJoin('users', 'users.id', '=', 'posts.user_id')
          .leftJoin('comments', 'comments.post_id', '=', 'posts.id')
          .leftJoin('likes', 'likes.post_id', '=', 'posts.id')
          .where('posts.is_active', '=', 1);

      for (final id in blockedIds) {
        postsQuery = postsQuery.where('posts.user_id', '!=', id);
      }

      final posts = await postsQuery
          .groupBy([
            'posts.id',
            'posts.user_id',
            'posts.caption',
            'posts.post_type',
            'posts.image_url',
            'posts.thumbnail_url',
            'posts.video_url',
            'posts.media_kind',
            'posts.storage_bucket',
            'posts.storage_path',
            'posts.mime_type',
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
        likedPostIds = (liked as List)
            .whereType<Map>()
            .map((l) => l['post_id']?.toString() ?? '')
            .toList();
      }

      final rows = (posts['data'] as List<dynamic>).whereType<Map>();
      final data = rows.map((post) {
        return {
          'id': post['id'],
          'user_id': post['user_id'],
          'user_name': post['user_name'],
          'user_username': post['user_username'],
          'user_avatar': post['user_avatar'],
          'user_is_verified': post['user_is_verified'],
          'caption': post['caption'],
          'post_type': post['post_type']?.trim(),
          'media': _decodeMediaText(
            post['media'],
            imageUrl: post['image_url']?.toString() ?? '',
            thumbnailUrl: post['thumbnail_url']?.toString() ?? '',
            videoUrl: post['video_url']?.toString() ?? '',
            mediaKind: post['media_kind']?.toString() ?? 'image',
            bucket: post['storage_bucket']?.toString() ?? '',
            path: post['storage_path']?.toString() ?? '',
            mimeType: post['mime_type']?.toString() ?? '',
          ),
          'image_url': post['image_url'],
          'thumbnail_url': post['thumbnail_url'] ?? '',
          'video_url': post['video_url'] ?? '',
          'media_kind': post['media_kind'] ?? 'image',
          'storage_bucket': post['storage_bucket'] ?? '',
          'storage_path': post['storage_path'] ?? '',
          'mime_type': post['mime_type'] ?? '',
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
            'posts.thumbnail_url',
            'posts.video_url',
            'posts.media_kind',
            'posts.storage_bucket',
            'posts.storage_path',
            'posts.mime_type',
            'posts.is_active',
            'posts.created_at',
          ])
          .selectRaw(
              'COALESCE(COUNT(DISTINCT comments.id), 0) AS comment_count, '
              'COALESCE(COUNT(DISTINCT likes.id), 0) AS like_count, '
              "COALESCE(MIN(posts.hashtags::TEXT), '[]') AS extracted_hashtags, "
              "COALESCE(MIN(posts.media::TEXT), '[]') AS media")
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
            'posts.thumbnail_url',
            'posts.video_url',
            'posts.media_kind',
            'posts.storage_bucket',
            'posts.storage_path',
            'posts.mime_type',
            'posts.is_active',
            'posts.created_at',
          ])
          .orderBy('posts.created_at', 'DESC')
          .paginate(limit, page);

      List<String> likedPostIds = [];
      if (authUserId.isNotEmpty) {
        final liked =
            await LikesModel().query().where('user_id', '=', authUserId).get();
        likedPostIds = (liked as List)
            .whereType<Map>()
            .map((l) => l['post_id']?.toString() ?? '')
            .toList();
      }

      final rows = (posts['data'] as List<dynamic>).whereType<Map>();
      final data = rows.map((post) {
        return {
          'id': post['id'],
          'user_id': post['user_id'],
          'caption': post['caption'],
          'post_type': post['post_type']?.trim(),
          'media': _decodeMediaText(
            post['media'],
            imageUrl: post['image_url']?.toString() ?? '',
            thumbnailUrl: post['thumbnail_url']?.toString() ?? '',
            videoUrl: post['video_url']?.toString() ?? '',
            mediaKind: post['media_kind']?.toString() ?? 'image',
            bucket: post['storage_bucket']?.toString() ?? '',
            path: post['storage_path']?.toString() ?? '',
            mimeType: post['mime_type']?.toString() ?? '',
          ),
          'image_url': post['image_url'],
          'thumbnail_url': post['thumbnail_url'] ?? '',
          'video_url': post['video_url'] ?? '',
          'media_kind': post['media_kind'] ?? 'image',
          'storage_bucket': post['storage_bucket'] ?? '',
          'storage_path': post['storage_path'] ?? '',
          'mime_type': post['mime_type'] ?? '',
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
      final payload = Map<String, dynamic>.from(request.body);
      final postId = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final media = _normalizeMediaInput(payload['media']);
      final legacyMedia = _legacyFieldsFromMedia(
        media,
        fallbackImageUrl: payload['image_url']?.toString() ?? '',
        fallbackThumbnailUrl: payload['thumbnail_url']?.toString() ?? '',
        fallbackVideoUrl: payload['video_url']?.toString() ?? '',
        fallbackMediaKind: payload['media_kind']?.toString() ?? 'image',
        fallbackBucket: payload['storage_bucket']?.toString() ?? '',
        fallbackPath: payload['storage_path']?.toString() ?? '',
        fallbackMimeType: payload['mime_type']?.toString() ?? '',
      );

      final body = <String, dynamic>{
        'id': postId,
        'user_id': authUserId,
        'caption': payload['caption']?.toString().trim() ?? '',
        'post_type': payload['post_type']?.toString().trim() ?? 'feed',
        'media': jsonEncode(media),
        'image_url': legacyMedia['image_url'],
        'thumbnail_url': legacyMedia['thumbnail_url'],
        'video_url': legacyMedia['video_url'],
        'media_kind': legacyMedia['media_kind'],
        'storage_bucket': legacyMedia['storage_bucket'],
        'storage_path': legacyMedia['storage_path'],
        'mime_type': legacyMedia['mime_type'],
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      };

      // Handle hashtags - extract from caption if not provided
      if (payload['hashtags'] == null) {
        final caption = body['caption'] as String? ?? '';
        final hashtags =
            RegExp(r'#\w+').allMatches(caption).map((m) => m.group(0)).toList();
        body['hashtags'] = jsonEncode(hashtags);
      } else {
        final hashtags = payload['hashtags'];
        body['hashtags'] = hashtags is String ? hashtags : jsonEncode(hashtags);
      }

      await Posts().query().insert(body);

      // Increment user bling_score for posting
      await User().query().where('id', '=', authUserId).update({
        'bling_score': await _getNewScore(authUserId, 10),
        'updated_at': now,
      });

      // Notify followers about new post
      unawaited(_notifyFollowers(
          authUserId, postId, body['caption'] as String? ?? ''));

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
  Future<Response> deletePost(Request request, [dynamic _]) async {
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
  Future<Response> toggleLike(Request request, [dynamic _]) async {
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
      final liker = await User().query().where('id', '=', authUserId).first();

      // Create notification for post owner (if not self-like)
      if (post['user_id'] != authUserId) {
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

      // Push notification
      if (post['user_id'] != authUserId) {
        unawaited(FcmService.instance.sendToUser(
          post['user_id'] as String,
          title: 'New Like',
          body: '${liker?['name'] ?? 'Someone'} liked your post',
          data: {'type': 'like', 'post_id': postId},
        ));
      }

      return Response.json({'message': 'Post liked', 'liked': true}, 200);
    }
  }

  /// POST /api/posts/:id/comment  (authenticated)
  Future<Response> addComment(Request request, [dynamic _]) async {
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

    final parentId = request.body['parent_id']?.toString();

    await connection!.statement(
      'INSERT INTO comments (id, user_id, post_id, parent_id, content, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7)',
      [
        commentId,
        authUserId,
        postId,
        parentId,
        request.body['content'],
        now,
        now
      ],
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

    // Push notification
    if (post['user_id'] != authUserId) {
      final commenterName = (await User()
              .query()
              .where('id', '=', authUserId)
              .first())?['name'] ??
          'Someone';
      unawaited(FcmService.instance.sendToUser(
        post['user_id'] as String,
        title: 'New Comment',
        body: '$commenterName commented on your post',
        data: {'type': 'comment', 'post_id': postId},
      ));
    }

    return Response.json({
      'message': 'Comment added',
      'comment_id': commentId,
    }, 201);
  }

  /// GET /api/posts/:id/comments
  Future<Response> getComments(Request request, [dynamic _]) async {
    final postId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;

    // Build excluded user IDs (people who blocked auth user or are blocked)
    final List<String> blockedIds = [];
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
      blockedIds.addAll((blockedByMe as List)
          .whereType<Map>()
          .map((r) => r['blocked_user_id'].toString()));
      blockedIds.addAll((blockedMe as List)
          .whereType<Map>()
          .map((r) => r['user_id'].toString()));
    }

    // Build exclusion clause
    final exclusionClause = blockedIds.isEmpty
        ? ''
        : 'AND c.user_id NOT IN (${blockedIds.map((id) => "'$id'").join(',')})';

    try {
      // Fetch top-level comments (no parent)
      final topLevel = await connection!.select(
        '''SELECT c.id, c.content, c.parent_id, c.created_at,
               u.id as user_id, u.name as user_name, u.username, u.avatar as user_avatar,
               (SELECT COUNT(*) FROM comments r WHERE r.parent_id = c.id::text) as reply_count
           FROM comments c
           JOIN users u ON u.id = c.user_id
           WHERE c.post_id = \$1 AND (c.parent_id IS NULL OR c.parent_id = '')
             $exclusionClause
           ORDER BY c.created_at ASC
           LIMIT \$2 OFFSET \$3''',
        [postId, limit, (page - 1) * limit],
      );

      if (topLevel.isEmpty) {
        return Response.json({'comments': []}, HttpStatus.ok);
      }

      // Batch fetch replies for all top-level comments
      final parentIds = topLevel.map((c) => "'${c['id']}'").join(',');
      final replies = await connection!.select(
        '''SELECT c.id, c.content, c.parent_id, c.created_at,
               u.id as user_id, u.name as user_name, u.username, u.avatar as user_avatar
           FROM comments c
           JOIN users u ON u.id = c.user_id
           WHERE c.parent_id IN ($parentIds)
             $exclusionClause
           ORDER BY c.created_at ASC''',
        [],
      );

      // Group replies by parent_id
      final replyMap = <String, List<Map<String, dynamic>>>{};
      for (final r in replies) {
        final pid = r['parent_id'].toString();
        replyMap.putIfAbsent(pid, () => []).add(r);
      }

      final result = topLevel.map((c) {
        final cid = c['id'].toString();
        return {
          'id': cid,
          'content': c['content'],
          'parent_id': null,
          'user_id': c['user_id'],
          'user_name': c['user_name'],
          'username': c['username'],
          'user_avatar': c['user_avatar'],
          'created_at': c['created_at'].toString(),
          'reply_count': c['reply_count'] ?? 0,
          'replies': (replyMap[cid] ?? [])
              .map((r) => {
                    'id': r['id'],
                    'content': r['content'],
                    'parent_id': r['parent_id'],
                    'user_id': r['user_id'],
                    'user_name': r['user_name'],
                    'username': r['username'],
                    'user_avatar': r['user_avatar'],
                    'created_at': r['created_at'].toString(),
                    'reply_count': 0,
                    'replies': [],
                  })
              .toList(),
        };
      }).toList();

      return Response.json({'comments': result}, HttpStatus.ok);
    } catch (e) {
      return Response.json(
          {'message': 'Error fetching comments', 'error': e.toString()}, 500);
    }
  }

  /// GET /api/posts/:id  — single post detail (authenticated)
  Future<Response> getPost(Request request, [dynamic _]) async {
    final postId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    try {
      final rows = await connection!.select('''
        SELECT p.id, p.user_id, p.caption, p.post_type, p.image_url, p.media::TEXT AS media,
               p.thumbnail_url, p.video_url, p.media_kind,
               p.storage_bucket, p.storage_path, p.mime_type,
               p.is_active, p.created_at, p.hashtags::TEXT AS extracted_hashtags,
               u.name AS user_name, u.username AS user_username,
               u.avatar AS user_avatar, u.is_verified AS user_is_verified,
               COALESCE((SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id::text), 0) AS comment_count,
               COALESCE((SELECT COUNT(*) FROM likes l WHERE l.post_id = p.id::text), 0) AS like_count
        FROM posts p
        JOIN users u ON u.id = p.user_id
        WHERE p.id::text = \$1 AND p.is_active = 1
      ''', [postId]);

      if (rows.isEmpty) return Response.json({'message': 'Not found'}, 404);

      final p = rows.first;
      bool isLiked = false;
      if (authUserId.isNotEmpty) {
        final liked = await LikesModel()
            .query()
            .where('user_id', '=', authUserId)
            .where('post_id', '=', postId)
            .first();
        isLiked = liked != null;
      }

      return Response.json({
        'post': {
          'id': p['id']?.toString(),
          'user_id': p['user_id']?.toString(),
          'user_name': p['user_name'],
          'user_username': p['user_username'],
          'user_avatar': p['user_avatar'],
          'user_is_verified': p['user_is_verified'],
          'caption': p['caption'],
          'post_type': p['post_type']?.toString().trim(),
          'media': _decodeMediaText(
            p['media'],
            imageUrl: p['image_url']?.toString() ?? '',
            thumbnailUrl: p['thumbnail_url']?.toString() ?? '',
            videoUrl: p['video_url']?.toString() ?? '',
            mediaKind: p['media_kind']?.toString() ?? 'image',
            bucket: p['storage_bucket']?.toString() ?? '',
            path: p['storage_path']?.toString() ?? '',
            mimeType: p['mime_type']?.toString() ?? '',
          ),
          'image_url': p['image_url'],
          'thumbnail_url': p['thumbnail_url'] ?? '',
          'video_url': p['video_url'] ?? '',
          'media_kind': p['media_kind'] ?? 'image',
          'storage_bucket': p['storage_bucket'] ?? '',
          'storage_path': p['storage_path'] ?? '',
          'mime_type': p['mime_type'] ?? '',
          'is_active': p['is_active'],
          'created_at': p['created_at'].toString(),
          'comment_count': p['comment_count'] ?? 0,
          'like_count': p['like_count'] ?? 0,
          'extracted_hashtags': p['extracted_hashtags'] ?? '[]',
          'is_liked': isLiked,
          'item_type': 'post',
        }
      }, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// GET /api/posts/hashtag/:tag  (public)
  Future<Response> getPostsByHashtag(Request request, [dynamic _]) async {
    final rawTag = request.params()['tag'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '10') ?? 10;

    if (rawTag.isEmpty) {
      return Response.json({'message': 'tag is required'}, 422);
    }

    // Normalize tag: ensure it has a leading #
    final tag = rawTag.startsWith('#') ? rawTag : '#$rawTag';

    try {
      final offset = (page - 1) * limit;
      // Use JSONB containment to find posts whose hashtags array includes the tag
      final rows = await connection!.select(
        '''SELECT p.id, p.user_id, p.caption, p.post_type, p.image_url, p.media::TEXT AS media,
                  p.thumbnail_url, p.video_url, p.media_kind,
                  p.storage_bucket, p.storage_path, p.mime_type,
                  p.is_active, p.created_at, p.hashtags::TEXT AS extracted_hashtags,
                  u.name AS user_name, u.username AS user_username,
                  u.avatar AS user_avatar, u.is_verified AS user_is_verified,
                  COALESCE((SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id::text), 0) AS comment_count,
                  COALESCE((SELECT COUNT(*) FROM likes l WHERE l.post_id = p.id::text), 0) AS like_count
           FROM posts p
           JOIN users u ON u.id = p.user_id
           WHERE p.is_active = 1
             AND p.hashtags::jsonb @> \$1::jsonb
           ORDER BY p.created_at DESC
           LIMIT \$2 OFFSET \$3''',
        [
          jsonEncode([tag]),
          limit,
          offset
        ],
      );

      List<String> likedPostIds = [];
      if (authUserId.isNotEmpty) {
        final liked =
            await LikesModel().query().where('user_id', '=', authUserId).get();
        likedPostIds = (liked as List)
            .whereType<Map>()
            .map((l) => l['post_id']?.toString() ?? '')
            .toList();
      }

      final data = rows.whereType<Map>().map((p) {
        return {
          'id': p['id'],
          'user_id': p['user_id'],
          'user_name': p['user_name'],
          'user_username': p['user_username'],
          'user_avatar': p['user_avatar'],
          'user_is_verified': p['user_is_verified'],
          'caption': p['caption'],
          'post_type': p['post_type']?.trim(),
          'media': _decodeMediaText(
            p['media'],
            imageUrl: p['image_url']?.toString() ?? '',
            thumbnailUrl: p['thumbnail_url']?.toString() ?? '',
            videoUrl: p['video_url']?.toString() ?? '',
            mediaKind: p['media_kind']?.toString() ?? 'image',
            bucket: p['storage_bucket']?.toString() ?? '',
            path: p['storage_path']?.toString() ?? '',
            mimeType: p['mime_type']?.toString() ?? '',
          ),
          'image_url': p['image_url'],
          'thumbnail_url': p['thumbnail_url'] ?? '',
          'video_url': p['video_url'] ?? '',
          'media_kind': p['media_kind'] ?? 'image',
          'storage_bucket': p['storage_bucket'] ?? '',
          'storage_path': p['storage_path'] ?? '',
          'mime_type': p['mime_type'] ?? '',
          'is_active': p['is_active'],
          'created_at': p['created_at'].toString(),
          'comment_count': p['comment_count'] ?? 0,
          'like_count': p['like_count'] ?? 0,
          'extracted_hashtags': p['extracted_hashtags'] ?? '[]',
          'is_liked': likedPostIds.contains(p['id']?.toString()),
          'item_type': 'post',
        };
      }).toList();

      return Response.json({
        'posts': {
          'data': data,
          'page': page,
          'per_page': limit,
          'has_more': data.length >= limit,
        }
      }, 200);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching posts by hashtag',
        'error': e.toString(),
      }, 500);
    }
  }

  Future<int> _getNewScore(String userId, int increment) async {
    final user = await User().query().where('id', '=', userId).first();
    final currentScore = (user?['bling_score'] as int?) ?? 0;
    return currentScore + increment;
  }

  List<Map<String, dynamic>> _normalizeMediaInput(dynamic rawMedia) {
    if (rawMedia is! List) return [];

    return rawMedia
        .whereType<Map>()
        .map((entry) =>
            entry.map((key, value) => MapEntry(key.toString(), value)))
        .map((media) {
          final kind = media['kind']?.toString().trim().isNotEmpty == true
              ? media['kind'].toString().trim()
              : media['media_kind']?.toString().trim() ?? 'image';
          final url = media['url']?.toString().trim().isNotEmpty == true
              ? media['url'].toString().trim()
              : media['media_url']?.toString().trim() ?? '';
          final thumbnailUrl =
              media['thumbnail_url']?.toString().trim().isNotEmpty == true
                  ? media['thumbnail_url'].toString().trim()
                  : (kind == 'image' ? url : '');

          return {
            'kind': kind,
            'url': url,
            'thumbnail_url': thumbnailUrl,
            'storage_bucket': media['storage_bucket']?.toString() ??
                media['bucket']?.toString() ??
                '',
            'storage_path': media['storage_path']?.toString() ??
                media['path']?.toString() ??
                '',
            'mime_type': media['mime_type']?.toString() ??
                media['mimeType']?.toString() ??
                '',
            'file_name': media['file_name']?.toString() ??
                media['fileName']?.toString() ??
                '',
          };
        })
        .where((media) => (media['url']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  Map<String, String> _legacyFieldsFromMedia(
    List<Map<String, dynamic>> media, {
    required String fallbackImageUrl,
    required String fallbackThumbnailUrl,
    required String fallbackVideoUrl,
    required String fallbackMediaKind,
    required String fallbackBucket,
    required String fallbackPath,
    required String fallbackMimeType,
  }) {
    if (media.isEmpty) {
      return {
        'image_url': fallbackImageUrl,
        'thumbnail_url': fallbackThumbnailUrl,
        'video_url': fallbackVideoUrl,
        'media_kind': fallbackMediaKind,
        'storage_bucket': fallbackBucket,
        'storage_path': fallbackPath,
        'mime_type': fallbackMimeType,
      };
    }

    final primary = media.first;
    final kind = primary['kind']?.toString() ?? 'image';
    final url = primary['url']?.toString() ?? '';
    final thumbnail = primary['thumbnail_url']?.toString() ?? '';

    return {
      'image_url': kind == 'image' ? url : '',
      'thumbnail_url':
          thumbnail.isNotEmpty ? thumbnail : (kind == 'image' ? url : ''),
      'video_url': kind == 'video' ? url : '',
      'media_kind': kind,
      'storage_bucket': primary['storage_bucket']?.toString() ?? '',
      'storage_path': primary['storage_path']?.toString() ?? '',
      'mime_type': primary['mime_type']?.toString() ?? '',
    };
  }

  List<Map<String, dynamic>> _decodeMediaText(
    dynamic rawText, {
    required String imageUrl,
    required String thumbnailUrl,
    required String videoUrl,
    required String mediaKind,
    required String bucket,
    required String path,
    required String mimeType,
  }) {
    if (rawText is String && rawText.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawText);
        final normalized = _normalizeMediaInput(decoded);
        if (normalized.isNotEmpty) return normalized;
      } catch (_) {}
    }

    final fallbackUrl = mediaKind == 'video' ? videoUrl : imageUrl;
    if (fallbackUrl.isEmpty) return [];

    return [
      {
        'kind': mediaKind,
        'url': fallbackUrl,
        'thumbnail_url': thumbnailUrl.isNotEmpty
            ? thumbnailUrl
            : (mediaKind == 'image' ? imageUrl : ''),
        'storage_bucket': bucket,
        'storage_path': path,
        'mime_type': mimeType,
      }
    ];
  }

  Future<void> _notifyFollowers(
      String userId, String postId, String caption) async {
    try {
      final poster = await User()
          .query()
          .select(['name'])
          .where('id', '=', userId)
          .first();
      final name = poster?['name'] as String? ?? 'Someone';
      final preview =
          caption.length > 60 ? '${caption.substring(0, 60)}…' : caption;

      final followers = await connection!.select(
        'SELECT follower_id FROM follows WHERE following_id = \$1',
        [userId],
      );
      final ids = followers.map((r) => r['follower_id'] as String).toList();
      if (ids.isEmpty) return;

      await FcmService.instance.sendToUsers(
        ids,
        title: '$name posted',
        body: preview.isNotEmpty ? preview : 'New post',
        data: {'type': 'new_post', 'post_id': postId, 'user_id': userId},
      );
    } catch (e) {
      print('[FCM] _notifyFollowers error: \$e');
    }
  }
}

final PostsController postsController = PostsController();
