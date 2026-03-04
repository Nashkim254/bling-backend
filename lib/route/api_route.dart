import 'package:bling/app/http/controllers/ad_controller.dart';
import 'package:bling/app/http/controllers/auth_controller.dart';
import 'package:bling/app/http/controllers/challenges_controller.dart';
import 'package:bling/app/http/controllers/chat_controller.dart';
import 'package:bling/app/http/controllers/follow_controller.dart';
import 'package:bling/app/http/controllers/leaderboard_controller.dart';
import 'package:bling/app/http/controllers/notification_controller.dart';
import 'package:bling/app/http/controllers/posts_controller.dart';
import 'package:bling/app/http/controllers/wallet_controller.dart';
import 'package:bling/app/http/middleware/authenticate.dart';
import 'package:vania/vania.dart';

class ApiRoute implements Route {
  @override
  void register() {
    Router.basePrefix('api');

    // ─── Public Auth Routes ───────────────────────────────────────────
    Router.post('/register', authController.register);
    Router.post('/login', authController.login);

    // ─── Public Routes ────────────────────────────────────────────────
    Router.get('/users', authController.getUsers);
    Router.get('/users/:id', authController.getUserById);
    Router.get('/leaderboard', leaderboardController.getLeaderboard);
    Router.get('/challenges', challengesController.getChallenges);
    Router.get('/ads', adController.getAds);
    Router.get('/bling/packages', walletController.getPackages);

    // ─── Authenticated Routes ─────────────────────────────────────────
    Router.group(() {
      // User profile
      Router.get('/user/profile', authController.getProfile);
      Router.put('/user/profile', authController.updateProfile);

      // Feed & Posts
      Router.get('/feed', postsController.getFeed);
      Router.get('/posts', postsController.getPosts);
      Router.post('/posts', postsController.createPost);
      Router.delete('/posts/:id', postsController.deletePost);
      Router.post('/posts/:id/like', postsController.toggleLike);
      Router.post('/posts/:id/comment', postsController.addComment);
      Router.get('/posts/:id/comments', postsController.getComments);

      // Challenges
      Router.post('/challenges', challengesController.createChallenge);
      Router.post('/challenges/:id/participate', challengesController.participate);

      // Wallet & Bling
      Router.get('/wallet', walletController.getWallet);
      Router.get('/wallet/transactions', walletController.getTransactions);
      Router.post('/bling/purchase', walletController.purchaseBling);
      Router.post('/bling/transfer', walletController.transferBling);

      // Follow
      Router.post('/follow/:userId', followController.follow);
      Router.delete('/follow/:userId', followController.unfollow);
      Router.get('/user/followers', followController.getFollowers);
      Router.get('/user/following', followController.getFollowing);

      // Chats (HTTP)
      Router.get('/chats', chatController.getConversations);
      Router.get('/chats/:userId', chatController.getMessages);

      // Notifications
      Router.get('/notifications', notificationController.getNotifications);
      Router.post('/notifications/read', notificationController.markRead);

      // Leaderboard (auth version includes my_rank)
      Router.get('/leaderboard/me', leaderboardController.getLeaderboard);
    }, middleware: [AuthenticateMiddleware()]);

    // ─── Legacy endpoints (keep backward compat) ─────────────────────
    Router.get('/get/posts', postsController.getPosts);
    Router.post('/create/post', postsController.createPost);
    Router.post('/create/challenge', challengesController.createChallenge);
  }
}
