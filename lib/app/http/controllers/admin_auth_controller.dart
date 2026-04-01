import 'dart:convert';
import 'dart:io';

import 'package:bling/app/models/user.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:vania/vania.dart';

class AdminAuthController extends Controller {
  Future<Response> login(Request request) async {
    request.validate({
      'password': 'required|string',
      'email': 'required|string',
    }, {
      'password.required': 'Password is required',
      'email.required': 'Email or username is required',
    });

    final body = request.body;
    final emailOrUsername = body['email'] as String;
    final password = body['password'] as String;

    var user = await User().query().where('email', '=', emailOrUsername).first();
    user ??=
        await User().query().where('username', '=', emailOrUsername).first();

    if (user == null || !Hash().verify(password, user['password'])) {
      return Response.json({'message': 'Invalid credentials'}, 401);
    }

    if ((user['is_admin'] as num?)?.toInt() != 1) {
      return Response.json({'message': 'Admin access required'}, 403);
    }

    final status = user['status']?.toString() ?? 'active';
    if (status != 'active') {
      return Response.json({'message': 'Admin account is not active'}, 403);
    }

    try {
      final auth = Auth().login(user);
      user['created_at'] = user['created_at'].toIso8601String();
      user['updated_at'] = user['updated_at'].toIso8601String();
      final token = await auth.createToken(
        expiresIn: const Duration(hours: 24),
        withRefreshToken: true,
      );

      final wallet =
          await Wallet().query().where('user_id', '=', user['id']).first();
      final blingBalance = wallet?['balance'] ?? 0;
      final roleRows = await connection!.select(
        '''
        SELECT r.name, r.permissions
        FROM admin_user_roles aur
        INNER JOIN admin_roles r ON r.id = aur.role_id
        WHERE aur.user_id = \$1 AND r.status = 'active'
        ORDER BY r.created_at ASC
        ''',
        [user['id']],
      );

      final permissions = <String>{};
      final roles = <String>[];
      for (final row in roleRows) {
        roles.add(row['name']?.toString() ?? '');
        final rawPermissions = row['permissions']?.toString() ?? '[]';
        final decoded = jsonDecode(rawPermissions);
        if (decoded is List) {
          permissions.addAll(decoded.map((item) => item.toString()));
        }
      }

      return Response.json({
        'token': token['access_token'],
        'refresh_token': token['refresh_token'],
        'expiry':
            DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        'user': {
          'id': user['id']?.toString(),
          'name': user['name']?.toString(),
          'username': user['username']?.toString(),
          'email': user['email']?.toString(),
          'avatar': user['avatar']?.toString(),
          'bling_balance': blingBalance,
          'is_admin': true,
          'roles': roles,
          'permissions': permissions.toList(),
        }
      }, HttpStatus.ok);
    } on JWTExpiredException {
      return Response.json({'message': 'Token expired'}, 401);
    } catch (e) {
      return Response.json(
        {'message': 'Error creating admin session', 'error': e.toString()},
        500,
      );
    }
  }
}

final AdminAuthController adminAuthController = AdminAuthController();
