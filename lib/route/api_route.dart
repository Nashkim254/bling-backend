import 'package:bling/app/http/controllers/auth_controller.dart';
import 'package:bling/app/http/controllers/home_controller.dart';
import 'package:bling/app/http/middleware/authenticate.dart';
import 'package:vania/vania.dart';

class ApiRoute implements Route {
  @override
  void register() {
    /// Base RoutePrefix
    Router.basePrefix('api');
    Router.post('/register', authController.register);
    Router.post('/login', authController.login);

    Router.group(() {
      Router.post('/get/posts', homeController.getPosts);
      Router.post('/create/post', homeController.createPost);
    }, middleware: [AuthenticateMiddleware()]);
  }
}
