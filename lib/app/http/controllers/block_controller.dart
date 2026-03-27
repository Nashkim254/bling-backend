import 'dart:io';

import 'package:bling/app/models/block_model.dart';
import 'package:bling/app/models/user.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class BlockController extends Controller {
  /// POST /api/block/:userId  — block a user
  Future<Response> blockUser(Request request, [dynamic _]) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    final targetId = request.params()['id']?.toString() ?? '';

    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);
    if (targetId == me) {
      return Response.json({'message': 'Cannot block yourself'}, 422);
    }

    final target = await User().query().where('id', '=', targetId).first();
    if (target == null) {
      return Response.json({'message': 'User not found'}, 404);
    }

    // Idempotent — don't re-insert if already blocked
    final existing = await BlockModel()
        .query()
        .where('user_id', '=', me)
        .where('blocked_user_id', '=', targetId)
        .first();

    if (existing == null) {
      final now = DateTime.now().toIso8601String();
      await BlockModel().query().insert({
        'id': const Uuid().v4(),
        'user_id': me,
        'blocked_user_id': targetId,
        'created_at': now,
        'updated_at': now,
      });
    }

    return Response.json({'message': 'User blocked'}, HttpStatus.ok);
  }

  /// DELETE /api/block/:userId  — unblock a user
  Future<Response> unblockUser(Request request, [dynamic _]) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    final targetId = request.params()['id']?.toString() ?? '';

    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    await BlockModel()
        .query()
        .where('user_id', '=', me)
        .where('blocked_user_id', '=', targetId)
        .delete();

    return Response.json({'message': 'User unblocked'}, HttpStatus.ok);
  }

  /// GET /api/blocks  — list users blocked by auth user
  Future<Response> listBlocked(Request request) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    try {
      final rows = await connection!.select('''
        SELECT u.id, u.name, u.username, u.avatar, b.created_at as blocked_at
        FROM blocks b
        JOIN users u ON u.id::text = b.blocked_user_id
        WHERE b.user_id = \$1
        ORDER BY b.created_at DESC
      ''', [me]);

      final users = rows
          .map((r) => {
                'id': r['id'],
                'name': r['name'],
                'username': r['username'],
                'avatar': r['avatar'],
                'blocked_at': r['blocked_at'].toString(),
              })
          .toList();

      return Response.json({'blocked_users': users}, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }
}

final BlockController blockController = BlockController();
