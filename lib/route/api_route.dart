import 'package:bling/app/http/controllers/account_controller.dart';
import 'package:bling/app/http/controllers/ad_controller.dart';
import 'package:bling/app/http/controllers/auth_controller.dart';
import 'package:bling/app/http/controllers/block_controller.dart';
import 'package:bling/app/http/controllers/otp_controller.dart';
import 'package:bling/app/http/controllers/challenges_controller.dart';
import 'package:bling/app/http/controllers/chat_controller.dart';
import 'package:bling/app/http/controllers/follow_controller.dart';
import 'package:bling/app/http/controllers/leaderboard_controller.dart';
import 'package:bling/app/http/controllers/notification_controller.dart';
import 'package:bling/app/http/controllers/posts_controller.dart';
import 'package:bling/app/http/controllers/purchase_controller.dart';
import 'package:bling/app/http/controllers/report_controller.dart';
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

    // ─── OTP & Password Reset ─────────────────────────────────────────
    Router.post('/otp/send', otpController.sendOtp);
    Router.post('/otp/verify', otpController.verifyOtp);
    Router.post('/auth/reset-password', authController.resetPassword);
    Router.post('/auth/refresh', authController.refreshToken);

    // ─── Public Routes ────────────────────────────────────────────────
    Router.get('/users', authController.getUsers);
    Router.get('/users/{id}', authController.getUserById);
    Router.get('/leaderboard', leaderboardController.getLeaderboard);
    Router.get('/challenges', challengesController.getChallenges);
    Router.get('/ads', adController.getAds);
    Router.get('/bling/packages', walletController.getPackages);
    Router.get('/posts/hashtag/{tag}', postsController.getPostsByHashtag);

    // ─── Authenticated Routes ─────────────────────────────────────────
    Router.group(() {
      // User profile
      Router.get('/user/profile', authController.getProfile);
      Router.put('/user/profile', authController.updateProfile);
      Router.put('/user/fcm-token', authController.updateFcmToken);
      Router.put('/user/location', authController.updateLocation);
      Router.get('/users/nearby', authController.getNearbyUsers);

      // Feed & Posts
      Router.get('/feed', postsController.getFeed);
      Router.get('/posts', postsController.getPosts);
      Router.post('/posts', postsController.createPost);
      Router.delete('/posts/{id}', postsController.deletePost);
      Router.post('/posts/{id}/like', postsController.toggleLike);
      Router.post('/posts/{id}/comment', postsController.addComment);
      Router.get('/posts/{id}/comments', postsController.getComments);

      // Challenges
      Router.post('/challenges', challengesController.createChallenge);
      Router.post('/challenges/{id}/participate', challengesController.participate);

      // Wallet & Bling
      Router.get('/wallet', walletController.getWallet);
      Router.get('/wallet/transactions', walletController.getTransactions);
      Router.post('/bling/purchase', walletController.purchaseBling);
      Router.post('/bling/purchase/verify', purchaseController.verifyPurchase);
      Router.post('/bling/transfer', walletController.transferBling);

      // Follow
      Router.post('/follow/{userId}', followController.follow);
      Router.delete('/follow/{userId}', followController.unfollow);
      Router.get('/user/followers', followController.getFollowers);
      Router.get('/user/following', followController.getFollowing);

      // Messages
      Router.delete('/messages/{id}', chatController.deleteMessage);
      Router.put('/messages/{id}', chatController.editMessage);
      Router.post('/messages/{id}/react', chatController.reactToMessage);
      // File upload
      Router.post('/upload', chatController.uploadFile);

      // Notifications
      Router.get('/notifications', notificationController.getNotifications);
      Router.post('/notifications/read', notificationController.markRead);

      // Leaderboard (auth version includes my_rank)
      Router.get('/leaderboard/me', leaderboardController.getLeaderboard);

      // Block
      Router.post('/block/{userId}', blockController.blockUser);
      Router.delete('/block/{userId}', blockController.unblockUser);
      Router.get('/blocks', blockController.listBlocked);

      // Report
      Router.post('/report/user/{userId}', reportController.reportUser);
      Router.post('/report/post/{postId}', reportController.reportPost);

      // Account management
      Router.delete('/account', accountController.deleteAccount);
      Router.post('/account/disable', accountController.disableAccount);

      // Ads — campaign management & tracking
      Router.post('/ads', adController.createAd);
      Router.get('/ads/my', adController.myCampaigns);
      Router.put('/ads/{id}', adController.updateAd);
      Router.post('/ads/{id}/impression', adController.recordImpression);
      Router.post('/ads/{id}/click', adController.recordClick);
    }, middleware: [AuthenticateMiddleware()]);

    // ─── Chats — flat routes inside auth middleware group ────────────────────
    // NOTE: Vania cannot match /:param/sub-path inside a prefix group, so all
    // chat sub-routes use flat 2-segment names (no nested param paths).
    Router.group(() {
      // Conversation list/create/delete (2-segment max — safe)
      Router.get('/chats/archived', chatController.getArchivedConversations);
      Router.get('/chats', chatController.getConversations);
      Router.post('/chats', chatController.createConversation);
      Router.delete('/chats/{id}', chatController.deleteConversation);
      // Messages — flat: /chat-messages/{id}
      Router.get('/chat-messages/{id}', chatController.getMessages);
      Router.post('/chat-messages/{id}', chatController.sendMessage);
      // Actions — flat: /chat-<action>/{id}
      Router.post('/chat-pin/{id}', chatController.pinConversation);
      Router.post('/chat-unpin/{id}', chatController.unpinConversation);
      Router.post('/chat-archive/{id}', chatController.archiveConversation);
      Router.post('/chat-unarchive/{id}', chatController.unarchiveConversation);
      Router.post('/chat-read/{id}', chatController.markConversationRead);
    }, middleware: [AuthenticateMiddleware()]);

    // ─── Legacy endpoints (keep backward compat) ─────────────────────
    Router.get('/get/posts', postsController.getPosts);
    Router.post('/create/post', postsController.createPost);
    Router.post('/create/challenge', challengesController.createChallenge);
  }
}
