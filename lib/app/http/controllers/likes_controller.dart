import 'dart:io';

import 'package:bling/app/models/likes_model.dart';
import 'package:vania/vania.dart';

class LikesController extends Controller {


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
}

final LikesController likesController = LikesController();

