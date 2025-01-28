import 'dart:io';

import 'package:bling/app/models/comments_model.dart';
import 'package:vania/vania.dart';

class CommentsController extends Controller {
    Future<Response> createCommennt(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await CommentsModel().query().insert(body);
      return Response.json(
          {'message': 'comment created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating comment',
      }, 422);
    }
  }
}

final CommentsController commentsController = CommentsController();

