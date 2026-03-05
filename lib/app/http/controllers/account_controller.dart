import 'dart:io';

import 'package:bling/app/models/user.dart';
import 'package:vania/vania.dart';

class AccountController extends Controller {
  /// DELETE /api/account  — permanently delete account (soft delete)
  Future<Response> deleteAccount(Request request) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final now = DateTime.now().toIso8601String();
    await User().query().where('id', '=', me).update({
      'status': 'deleted',
      'deleted_at': now,
      'updated_at': now,
      // Anonymize PII
      'name': 'Deleted User',
      'username': 'deleted_$me',
      'email': 'deleted_${me}@deleted.bling',
      'avatar': '',
      'bio': '',
    });

    return Response.json({'message': 'Account deleted'}, HttpStatus.ok);
  }

  /// POST /api/account/disable  — temporarily disable account
  Future<Response> disableAccount(Request request) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final now = DateTime.now().toIso8601String();
    await User().query().where('id', '=', me).update({
      'status': 'disabled',
      'updated_at': now,
    });

    return Response.json({'message': 'Account disabled'}, HttpStatus.ok);
  }
}

final AccountController accountController = AccountController();
