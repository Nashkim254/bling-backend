import 'dart:io';

import 'package:bling/app/models/challenges_model.dart';
import 'package:vania/vania.dart';

class ChallengesController extends Controller {
  Future<Response> createChallenge(Request request) async {
    Map<String, dynamic> body = request.body;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();
    try {
      await ChallengesModel().query().insert(body);
      return Response.json({'message': 'challenge created successfully'}, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error creating challenge',
      }, 422);
    }
  }
}

final ChallengesController challengesController = ChallengesController();
