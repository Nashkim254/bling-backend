import 'dart:io';

import 'package:bling/app/models/report_model_db.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class ReportController extends Controller {
  /// POST /api/report/user/:userId
  Future<Response> reportUser(Request request, [dynamic _]) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    final targetId = request.params()['id']?.toString() ?? '';
    final reason = request.body['reason']?.toString() ?? '';

    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);
    if (targetId == me) {
      return Response.json({'message': 'Cannot report yourself'}, 422);
    }

    // Prevent duplicate open reports
    final existing = await ReportModelDb()
        .query()
        .where('reporter_id', '=', me)
        .where('reported_type', '=', 'user')
        .where('reported_id', '=', targetId)
        .where('status', '=', 'pending')
        .first();

    if (existing != null) {
      return Response.json({'message': 'Already reported'}, HttpStatus.ok);
    }

    final now = DateTime.now().toIso8601String();
    await ReportModelDb().query().insert({
      'id': const Uuid().v4(),
      'reporter_id': me,
      'reported_type': 'user',
      'reported_id': targetId,
      'reason': reason,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });

    return Response.json({'message': 'Report submitted'}, HttpStatus.ok);
  }

  /// POST /api/report/post/:postId
  Future<Response> reportPost(Request request, [dynamic _]) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    final postId = request.params()['id']?.toString() ?? '';
    final reason = request.body['reason']?.toString() ?? '';

    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final existing = await ReportModelDb()
        .query()
        .where('reporter_id', '=', me)
        .where('reported_type', '=', 'post')
        .where('reported_id', '=', postId)
        .where('status', '=', 'pending')
        .first();

    if (existing != null) {
      return Response.json({'message': 'Already reported'}, HttpStatus.ok);
    }

    final now = DateTime.now().toIso8601String();
    await ReportModelDb().query().insert({
      'id': const Uuid().v4(),
      'reporter_id': me,
      'reported_type': 'post',
      'reported_id': postId,
      'reason': reason,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });

    return Response.json({'message': 'Report submitted'}, HttpStatus.ok);
  }
}

final ReportController reportController = ReportController();
