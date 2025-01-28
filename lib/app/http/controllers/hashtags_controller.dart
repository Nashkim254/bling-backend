import 'dart:io';

import 'package:bling/app/models/hashtags_model.dart';
import 'package:vania/vania.dart';

class HashtagsController extends Controller {
    Future<Response> createHashtag(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await HashtagsModel().query().insert(body);
      return Response.json(
          {'message': 'hashtag created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating hashtag',
      }, 422);
    }
  }
}

final HashtagsController hashtagsController = HashtagsController();

