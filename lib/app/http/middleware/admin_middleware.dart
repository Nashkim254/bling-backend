import 'package:bling/app/models/user.dart';
import 'package:vania/vania.dart';

class AdminMiddleware extends Middleware {
  @override
  Future handle(Request request) async {
    final userId = request.input('auth_user_id')?.toString() ?? '';
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final user = await User().query().where('id', '=', userId).first();
    if (user == null) {
      return Response.json({'message': 'User not found'}, 404);
    }

    if ((user['is_admin'] as num?)?.toInt() != 1) {
      return Response.json({'message': 'Admin access required'}, 403);
    }

    if ((user['status']?.toString() ?? 'active') != 'active') {
      return Response.json({'message': 'Admin account is not active'}, 403);
    }

    request.merge({
      'auth_admin_id': userId,
      'auth_admin_name': user['name']?.toString() ?? '',
    });
  }
}
