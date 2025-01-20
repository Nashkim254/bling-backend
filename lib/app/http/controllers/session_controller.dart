import 'package:bling/app/models/session.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class SessionController extends Controller {
  var uuid = Uuid();

  Future<Map<String, dynamic>> createSession({required String userId}) async {
    String token = HasApiTokens().createToken()['access_token'];
    print("Token: $token");
    Map<String, dynamic> values = {
      'user_id': userId,
      'status': 'active',
      'type': 'user',
      'token': token,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
      'expires_at': DateTime.now().add(
        const Duration(hours: 1),
      ),
    };
    await Session().query().insert(values);
    return values;
  }

  Future<Response> store(Request request) async {
    return Response.json({});
  }

  Future<Response> getSessionById(int id) async {
    var session = await Session().query().where('id', '==', id).select([
      'id',
      'user_id',
      'status',
      'type',
      'expires_at',
      'token',
      'created_at',
      'updated_at'
    ]).first();
    return Response.json(session);
  }

  Future<Response> getSessionByToken(String token) async {
    var session = await Session().query().where('token', '==', token).select([
      'id',
      'user_id',
      'status',
      'type',
      'expires_at',
      'token',
      'created_at',
      'updated_at'
    ]).first();
    return Response.json(session);
  }

  Future<Map<String, dynamic>> updateSession(
      {required String userId,
      required String status,
      required String type,
      required String id}) async {
    Map<String, dynamic> body = {
      'status': status,
      'userId': userId,
      'type': type,
    };
    await Session().query().where('id', '==', id).update(body);

    return body;
  }

  Future<Map<String, dynamic>> destroy(int id) async {
    await Session().query().where('id', '==', id).delete();
    Map<String, dynamic> body = {
      'id': id,
      'status': 'deleted',
    };
    return body;
  }
}

final SessionController sessionController = SessionController();
