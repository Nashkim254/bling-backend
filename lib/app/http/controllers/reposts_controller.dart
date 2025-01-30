import 'dart:io';

import 'package:bling/app/models/reposts_model.dart';
import 'package:vania/vania.dart';

class RepostsController extends Controller {

  Future<Response> createRepost(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await RepostsModel().query().insert(body);
      return Response.json({'message': 'Repost created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating repost',
      }, 422);
    }
  }


    Future<Response> getReposts(Request request) async {
    // Retrieve userId from the request input
    String? userId = request.input('userId');
    int page = int.parse(request.input('page') ?? '1');
    int limit = int.parse(request.input('limit') ?? '10');
 
    // Check if userId is provided and not empty
    if (userId != null && userId.isNotEmpty) {
      try {
        // Fetch posts with related comments, likes, and hashtags
        final reposts = await RepostsModel()
            .query()
            .select()
            .join('comments', 'comments.user_id', '=', 'users.id')
            .join('likes', 'likes.user_id', '=', 'users.id')
            .join('hashtags', 'hashtags.user_id', '=', 'users.id')
            .groupBy('posts.id')
            .where('user_id', '=', userId)
            .paginate(limit, page);

        // Return the posts in a JSON response
        return Response.json({'reposts': reposts}, HttpStatus.ok);
      } catch (e) {
        // Handle errors gracefully
        return Response.json({
          'message': 'An error occurred while fetching reposts',
          'error': e.toString(),
        }, HttpStatus.internalServerError);
      }
    }

    // Return a response for malformed requests
    return Response.json({
      'message': 'Malformed request: userId is required',
    }, HttpStatus.unprocessableEntity);
  }


}

final RepostsController repostsController = RepostsController();
