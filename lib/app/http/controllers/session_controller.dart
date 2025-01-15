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
      'expires_at': DateTime.now().add(
        const Duration(hours: 1),
      ),
    };
    Session().query().insert(values);
    return values;
  }

  Future<Response> store(Request request) async {
    return Response.json({});
  }

  Future<Response> show(int id) async {
    return Response.json({});
  }

  Future<Response> edit(int id) async {
    return Response.json({});
  }

  Future<Response> updateSession({required String userId,required String status, }) async {
    return Response.json({});
  }

  Future<Response> destroy(int id) async {
    return Response.json({});
  }
}

final SessionController sessionController = SessionController();
