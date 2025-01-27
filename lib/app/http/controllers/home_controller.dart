import 'dart:io';

import 'package:bling/app/models/likes_model.dart';
import 'package:bling/app/models/posts.dart';
import 'package:bling/app/models/reposts_model.dart';
import 'package:vania/vania.dart';

class HomeController extends Controller {


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

  Future<Response> createLike(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await LikesModel().query().insert(body);
      return Response.json(
          {'message': 'like created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating post',
      }, 422);
    }
  }

  Future<Response> createRepost(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await RepostsModel().query().insert(body);
      return Response.json(
          {'message': 'Repost created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating post',
      }, 422);
    }
  }

  Future<Response> getReposts(Request req) async {
    String userId = req.input('userId');
    if (userId.isNotEmpty) {
      final reposts =
          await RepostsModel().query().where('user_id', '=', userId).get();
      return Response.json({'reposts': reposts}, HttpStatus.ok);
    }
    return Response.json({
      'message': 'malformed request',
    }, 422);
  }
}

final HomeController homeController = HomeController();
