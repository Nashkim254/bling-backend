import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:vania/vania.dart';

class AuthenticateMiddleware extends Middleware {
  @override
  Future handle(Request request) async {
    final authHeader = request.header('Authorization');
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    try {
      final token = authHeader.substring(7);
      await Auth().check(token, isCustomToken: true);
      final userId = Auth().id()?.toString() ?? '';
      if (userId.isEmpty) {
        return Response.json({'message': 'Token invalid or expired'}, 401);
      }
      request.merge({'auth_user_id': userId});
    } on JWTExpiredException {
      return Response.json({'message': 'Token expired'}, 401);
    } catch (e) {
      return Response.json(
          {'message': 'Unauthenticated', 'error': e.toString()}, 401);
    }
  }
}
