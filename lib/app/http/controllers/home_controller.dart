import 'package:bling/app/models/posts.dart';
import 'package:vania/vania.dart';

class HomeController extends Controller {
  Future<Response> getPosts(Request request) async {
    String userId = request.input('userId');
    if (userId.isNotEmpty) {
      final posts = await Posts().query().get();
    }
    return Response.json({});
  }
}

final HomeController homeController = HomeController();
