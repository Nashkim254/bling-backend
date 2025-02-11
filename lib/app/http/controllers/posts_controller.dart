import 'dart:io';

import 'package:vania/vania.dart';

import 'package:bling/app/models/posts.dart';

class PostsController extends Controller {
  Future<Response> getPosts(Request request) async {
    // Retrieve userId from the request input
    String? userId = request.input('userId');
    int page = int.parse(request.input('page') ?? '1');
    int limit = int.parse(request.input('limit') ?? '10');

    // Check if userId is provided and not empty
    if (userId != null && userId.isNotEmpty) {
      try {
        // Fetch posts with related comments, likes, and hashtags
        final posts = await Posts()
            .query()
            .join('comments', 'comments.user_id', '=', 'users.id')
            .join('likes', 'likes.user_id', '=', 'users.id')
            .join('hashtags', 'hashtags.user_id', '=', 'users.id')
            .where( 'user_id', '=',  userId)
            .groupBy('posts.id')
            .paginate(limit, page);

        // Return the posts in a JSON response
        return Response.json({'posts': posts}, HttpStatus.ok);
      } catch (e) {
        // Handle errors gracefully
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

// Function to Generate Signed URL
  Future<String> generateSignedUrl(String fileName) async {
    return '';
  }

  Future<Response> createPost(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await Posts().query().insert(body);
      return Response.json({'message': 'Post created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating post',
      }, 422);
    }
  }
}

final PostsController postsController = PostsController();
