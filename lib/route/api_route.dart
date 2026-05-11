import 'package:bling/app/http/controllers/account_controller.dart';
import 'package:bling/app/http/controllers/ad_controller.dart';
import 'package:bling/app/http/controllers/admin_auth_controller.dart';
import 'package:bling/app/http/controllers/admin_controller.dart';
import 'package:bling/app/http/controllers/auth_controller.dart';
import 'package:bling/app/http/controllers/block_controller.dart';
import 'package:bling/app/http/controllers/otp_controller.dart';
import 'package:bling/app/http/controllers/challenges_controller.dart';
import 'package:bling/app/http/controllers/chat_controller.dart';
import 'package:bling/app/http/controllers/customization_controller.dart';
import 'package:bling/app/http/controllers/follow_controller.dart';
import 'package:bling/app/http/controllers/groups_controller.dart';
import 'package:bling/app/http/controllers/leaderboard_controller.dart';
import 'package:bling/app/http/controllers/notification_controller.dart';
import 'package:bling/app/http/controllers/posts_controller.dart';
import 'package:bling/app/http/controllers/purchase_controller.dart';
import 'package:bling/app/http/controllers/report_controller.dart';
import 'package:bling/app/http/controllers/reposts_controller.dart';
import 'package:bling/app/http/controllers/support_controller.dart';
import 'package:bling/app/http/controllers/wallet_controller.dart';
import 'package:bling/app/http/middleware/authenticate.dart';
import 'package:bling/app/http/middleware/admin_middleware.dart';
import 'package:vania/vania.dart';

class ApiRoute implements Route {
  @override
  void register() {
    Router.basePrefix('api');

    // ─── Public Auth Routes ───────────────────────────────────────────
    Router.post('/register', authController.register);
    Router.post('/login', authController.login);
    Router.post('/admin/login', adminAuthController.login);

    // ─── OTP & Password Reset ─────────────────────────────────────────
    Router.post('/otp/send', otpController.sendOtp);
    Router.post('/otp/verify', otpController.verifyOtp);
    Router.post('/auth/reset-password', authController.resetPassword);
    Router.post('/auth/refresh', authController.refreshToken);

    // ─── Public Routes ────────────────────────────────────────────────
    Router.get('/users', authController.getUsers);
    Router.get('/leaderboard', leaderboardController.getLeaderboard);
    Router.get('/challenges', challengesController.getChallenges);
    Router.get('/ads', adController.getAds);
    Router.get('/bling/packages', walletController.getPackages);
    Router.get('/posts/hashtag/{tag}', postsController.getPostsByHashtag);

    // ─── Authenticated Routes ─────────────────────────────────────────
    Router.group(() {
      Router.get('/admin/dashboard', adminController.getDashboard);
      Router.get('/admin/settings/roles', adminController.getRoles);
      Router.post('/admin/settings/roles', adminController.createRole);
      Router.put(
        '/admin/settings/roles/{id}/status',
        adminController.toggleRoleStatus,
      );
      Router.get('/admin/settings/users', adminController.getSystemUsers);
      Router.post('/admin/settings/users', adminController.createSystemUser);
      Router.put(
        '/admin/settings/users/{id}/status',
        adminController.toggleSystemUserStatus,
      );
      Router.get('/admin/resources/avatars', adminController.getAvatars);
      Router.post('/admin/resources/avatars', adminController.createAvatar);
      Router.get('/admin/resources/avatars/{id}', adminController.getAvatar);
      Router.post(
        '/admin/resources/avatars/{id}/accessories',
        adminController.createAccessory,
      );
      Router.put(
        '/admin/resources/accessories/{id}',
        adminController.updateAccessory,
      );
      Router.get(
        '/admin/resources/leaderboards',
        adminController.getLeaderboards,
      );
      Router.post(
        '/admin/resources/leaderboards',
        adminController.createLeaderboard,
      );
      Router.get(
        '/admin/resources/leaderboards/{id}',
        adminController.getLeaderboard,
      );
      Router.get('/admin/resources/levels', adminController.getLevels);
      Router.post('/admin/resources/levels', adminController.createLevel);
      Router.get('/admin/resources/levels/{id}', adminController.getLevel);
      Router.put('/admin/resources/levels/{id}', adminController.updateLevel);
      Router.get('/admin/notifications', adminController.getAdminNotifications);
      Router.post(
        '/admin/notifications/{id}/process',
        adminController.processNotification,
      );
      Router.post(
        '/admin/notifications/{id}/reply',
        adminController.replyToSupportNotification,
      );
      Router.get('/admin/transactions', adminController.getAdminTransactions);
      Router.post(
        '/admin/transactions/{id}/resolve',
        adminController.resolveTransaction,
      );
      Router.post(
        '/admin/transactions/{id}/reverse',
        adminController.reverseTransaction,
      );
      Router.get('/admin/groups', groupsController.getAdminGroups);
      Router.post('/admin/groups', groupsController.createAdminGroup);
      Router.put('/admin/groups/{id}', groupsController.updateAdminGroup);
    }, middleware: [AuthenticateMiddleware(), AdminMiddleware()]);

    Router.group(() {
      // User profile
      Router.get('/user/profile', authController.getProfile);
      Router.put('/user/profile', authController.updateProfile);
      Router.post('/user/verification/purchase',
          authController.purchaseVerificationBadge);
      Router.put('/user/fcm-token', authController.updateFcmToken);
      Router.put('/user/location', authController.updateLocation);
      Router.get('/users/nearby', authController.getNearbyUsers);
      Router.get('/users/{id}', authController.getUserById);

      // Feed & Posts
      Router.get('/feed', postsController.getFeed);
      Router.get('/reels', postsController.getReels);
      Router.post('/feed/interactions', postsController.recordFeedInteraction);
      Router.get('/posts', postsController.getPosts);
      Router.post('/posts', postsController.createPost);
      Router.put('/posts/{id}', postsController.updatePost);
      Router.get('/posts/{id}', postsController.getPost);
      Router.delete('/posts/{id}', postsController.deletePost);
      Router.post('/posts/{id}/like', postsController.toggleLike);
      Router.post('/posts/{id}/comment', postsController.addComment);
      Router.post('/posts/{id}/repost', repostsController.createRepost);
      Router.get('/posts/{id}/comments', postsController.getComments);

      // Challenges
      Router.get('/challenges/{id}', challengesController.getChallenge);
      Router.post('/challenges', challengesController.createChallenge);
      Router.post(
          '/challenges/{id}/participate', challengesController.participate);
      Router.post('/challenges/{id}/award', challengesController.awardWinner);

      // Groups
      Router.get('/groups', groupsController.getGroups);
      Router.post('/groups', groupsController.createGroup);
      Router.get('/groups/{id}', groupsController.getGroup);
      Router.post('/groups/{id}/join', groupsController.joinGroup);
      Router.post('/groups/{id}/leave', groupsController.leaveGroup);
      Router.get('/groups/{id}/requests', groupsController.getGroupRequests);
      Router.post(
        '/groups/{id}/requests/{userId}',
        groupsController.handleGroupRequest,
      );

      // Wallet & Bling
      Router.get('/wallet', walletController.getWallet);
      Router.get('/wallet/transactions', walletController.getTransactions);
      Router.post('/bling/purchase', walletController.purchaseBling);
      Router.post('/bling/purchase/verify', purchaseController.verifyPurchase);
      Router.post('/bling/transfer', walletController.transferBling);
      Router.get('/customization/catalog', customizationController.getCatalog);
      Router.post(
        '/customization/avatars/{id}/purchase',
        customizationController.purchaseAvatar,
      );
      Router.post(
        '/customization/avatars/{id}/equip',
        customizationController.equipAvatar,
      );
      Router.post(
        '/customization/medals/{id}/purchase',
        customizationController.purchaseMedal,
      );
      Router.post(
        '/customization/accessories/{id}/purchase',
        customizationController.purchaseAccessory,
      );
      Router.post(
        '/customization/accessories/{id}/equip',
        customizationController.equipAccessory,
      );

      // Follow
      Router.post('/follow/{id}', followController.follow);
      Router.delete('/follow/{id}', followController.unfollow);
      Router.delete(
          '/follow/connection/{id}', followController.removeConnection);
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
      Router.post('/block/{id}', blockController.blockUser);
      Router.delete('/block/{id}', blockController.unblockUser);
      Router.get('/blocks', blockController.listBlocked);

      // Report
      Router.post('/report/user/{id}', reportController.reportUser);
      Router.post('/report/post/{id}', reportController.reportPost);

      // Account management
      Router.delete('/account', accountController.deleteAccount);
      Router.post('/account/disable', accountController.disableAccount);

      // Ads — campaign management & tracking
      Router.post('/ads', adController.createAd);
      Router.get('/ads/my', adController.myCampaigns);
      Router.put('/ads/{id}', adController.updateAd);
      Router.post('/ads/{id}/impression', adController.recordImpression);
      Router.post('/ads/{id}/click', adController.recordClick);

      // Support
      Router.post('/support/request', supportController.createRequest);
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
