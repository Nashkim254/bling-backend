import 'dart:io';

import 'package:bling/app/http/controllers/session_controller.dart';
import 'package:bling/app/models/user.dart';
import 'package:vania/vania.dart';

class AuthController extends Controller {
  Future<Response> register(Request request) async {
    request.validate({
      'name': 'required|string',
      'password': 'required|string',
      'email': 'required|email',
    }, {
      'name.required': 'Name is required',
      'name.string': 'Name must be a string',
      'password.required': 'Password is required',
      'email.required': 'Email is required',
      'email.email': 'Invalid email format'
    });
    Map<String, dynamic> body = request.body;
    String email = body['email'];
    String password = body['password'];
    var user = await User().query().where('email', '=', email).first();
    if (user != null) {
      Map<String, String> responseBody = {
        'message': 'User already exists',
      };
      return Response.json(responseBody, 409);
    }
    var hashedPass = Hash().make(password);
    body['password'] = hashedPass;
    body['created_at'] = DateTime.now();
    body['updated_at'] = DateTime.now();

    await User().query().insert(body);

    Map<String, String> responseBody = {
      'message': 'User registered successfully',
    };
    return Response.json(responseBody, HttpStatus.ok);
  }

  Future<Response> login(Request request) async {
    request.validate({
      'password': 'required|string',
      'email': 'required|email',
    }, {
      'password.required': 'Password is required',
      'email.required': 'Email is required',
      'email.email': 'Invalid email format'
    });
    Map<String, dynamic> body = request.body;
    String email = body['email'];
    String password = body['password'];
    var user = await User().query().where('email', '=', email).first();
    if (user == null) {
      Map<String, String> responseBody = {
        'message': 'User does not exists',
      };
      return Response.json(responseBody, 404);
    }
    if (!Hash().verify(password, user['password'])) {
      Map<String, String> responseBody = {
        'message': 'Unauthorized',
      };
      return Response.json(responseBody, HttpStatus.unauthorized);
    }
       print("session: ${user['id']}");
    Map<String, dynamic> session = await SessionController().createSession(
      userId: user['id'].toString(),
    );
    print("session: $session");
    Map<String, dynamic> result = {
      'token': session['token'],
      'expiry': session['expires_at'],
      'username': user['username'],
    };

    return Response.json(result, HttpStatus.ok);
  }
}

final AuthController authController = AuthController();
