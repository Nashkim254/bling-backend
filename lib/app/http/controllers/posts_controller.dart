import 'dart:io';

import 'package:vania/vania.dart';

import 'package:bling/app/models/posts.dart';

class PostsController extends Controller {
  Future<Response> getPosts(Request request) async {
    // Retrieve userId from the request input
    String? userId = request.input('userId');
    int page = request.input('page') ?? 1;
    int limit = request.input('limit') ?? 10;
    print(page);
    print(limit);

    // Check if userId is provided and not empty
    if (userId != null && userId.isNotEmpty) {
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
                'COALESCE(COUNT(DISTINCT hashtags.id), 0) AS hashtag_count, '
                'MAX(posts.hashtags::TEXT) AS extracted_hashtags ') // ✅ Fixed here
            .leftJoin('comments', 'comments.post_id', '=', 'posts.id')
            .leftJoin('likes', 'likes.post_id', '=', 'posts.id')
            .leftJoin('hashtags', 'hashtags.post_id', '=', 'posts.id')
            .where('posts.user_id', '=', userId)
            .groupBy([
              'posts.id',
              'posts.user_id',
              'posts.caption',
              'posts.post_type',
              'posts.image_url',
              'posts.is_active',
              'posts.created_at'
              // ❌ Removed 'posts.hashtags' from GROUP BY
            ])
            .paginate(limit, page);

        // Return the posts in a JSON response
        return Response.json({
          'posts': {
            'total': posts['total'],
            'perPage': posts['perPage'],
            'page': posts['page'],
            'lastPage': posts['lastPage'],
            'previousPage': posts['previousPage'],
            'nextPage': posts['nextPage'],
            'nextLink':
                posts['nextLink']?.toString() ?? "", // Ensure it's a string
            'previousLink': posts['previousLink']?.toString() ?? "",
            'lastLink': posts['lastLink'] =
                posts['lastLink'] != null ? posts['lastLink'].toString() : "",
            'firstLink': posts['firstLink'] =
                posts['firstLink'] != null ? posts['firstLink'].toString() : "",
            'data': (posts['data'] as List<dynamic>)
                .map((post) => {
                      'id': post['id'],
                      'user_id': post['user_id'],
                      'caption': post['caption'],
                      'post_type': post['post_type']?.trim(), // Trim spaces
                      'image_url': post['image_url'],
                      'is_active': post['is_active'],
                      'created_at': post['created_at']
                          .toString(), // Ensure valid datetime string
                      'comment_count':
                          post['comment_count'] ?? 0, // Default to 0 if null
                      'like_count': post['like_count'] ?? 0,
                      'hashtag_count': post['hashtag_count'] ?? 0,
                      'extracted_hashtags': post['extracted_hashtags'] ?? []
                    })
                .toList()
          }
        }, HttpStatus.ok);
      } catch (e) {
        // Handle errors gracefully
        print('Detailed error: $e'); // Log for debugging
        return Response.json({
          'message': 'An error occurred while fetching posts',
          'error': e.toString(),
        }, HttpStatus.internalServerError);
      }
    }

    // Return a response for malformed requests
    return Response.json({
      'message': 'Malformed request: userId is required',
    }, HttpStatus.unprocessableEntity);
  }

  Future<Response> createPost(Request request) async {
    try {
      // 🔹 Decode JSON body
      Map<String, dynamic> body = request.body;
      body['created_at'] = DateTime.now().toIso8601String();
      body['updated_at'] = DateTime.now().toIso8601String();

      print("Processed Body: $body");

      await Posts().query().insert(body);
      return Response.json(
          {'message': 'Post created successfully'}, HttpStatus.ok);
    } catch (e) {
      print("Error: $e");
      return Response.json(
          {'message': 'Error creating post'}, HttpStatus.unprocessableEntity);
    }
  }
}

final PostsController postsController = PostsController();
