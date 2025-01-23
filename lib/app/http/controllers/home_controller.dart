import 'dart:io';

import 'package:bling/app/models/posts.dart';
import 'package:vania/vania.dart';

class HomeController extends Controller {
  Future<Response> getPosts(Request request) async {
    String userId = request.input('userId');
    if (userId.isNotEmpty) {
      final posts = await Posts().query().where('user_id', '=', userId).get();
      return Response.json({'posts': posts}, HttpStatus.ok);
    }
    return Response.json({
      'message': 'malformed request',
    }, 422);
  }

  Future<Response> createPost(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await Posts().query().insert(body);
      return Response.json(
          {'message': 'Post created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating post',
      }, 422);
    }
  }
}

final HomeController homeController = HomeController();
