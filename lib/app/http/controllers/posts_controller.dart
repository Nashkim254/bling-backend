import 'dart:io';

import 'package:bling/app/models/posts.dart';
import 'package:vania/vania.dart';

class PostsController extends Controller {
  Future<Response> index() async {
    return Response.json({'message': 'Hello World'});
  }

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

  Future<Response> store(Request request) async {
    return Response.json({});
  }

  Future<Response> show(int id) async {
    return Response.json({});
  }

  Future<Response> edit(int id) async {
    return Response.json({});
  }

  Future<Response> update(Request request, int id) async {
    return Response.json({});
  }

  Future<Response> destroy(int id) async {
    return Response.json({});
  }
}

final PostsController postsController = PostsController();
