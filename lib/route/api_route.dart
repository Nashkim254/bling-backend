import 'package:bling/app/http/controllers/auth_controller.dart';
import 'package:bling/app/http/controllers/challenges_controller.dart';
import 'package:bling/app/http/controllers/comments_controller.dart';
import 'package:bling/app/http/controllers/hashtags_controller.dart';
import 'package:bling/app/http/controllers/likes_controller.dart';
import 'package:bling/app/http/controllers/posts_controller.dart';
import 'package:bling/app/http/controllers/reposts_controller.dart';
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
      Router.get('/get/posts', postsController.getPosts);
      Router.post('/get/reposts', repostsController.getReposts);
      Router.post('/create/post', postsController.createPost);
      Router.post('/create/like', likesController.createLike);
      Router.post('/create/challenge', challengesController.createChallenge);
      Router.post('/create/hashtag', hashtagsController.createHashtag);
      Router.post('/create/comment', commentsController.createCommennt);
    }, middleware: [AuthenticateMiddleware()]);
  }
}
