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

  Future<Response> getReposts(Request req) async {
    String userId = req.input('userId');
    if (userId.isNotEmpty) {
      final reposts = await RepostsModel().query().where('user_id', '=', userId).get();
      return Response.json({'reposts': reposts}, HttpStatus.ok);
    }
    return Response.json({
      'message': 'malformed request',
    }, 422);
  }
}

final RepostsController repostsController = RepostsController();
