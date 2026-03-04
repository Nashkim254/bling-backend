import 'dart:io';

import 'package:bling/app/models/notification_model.dart';
import 'package:vania/vania.dart';

class NotificationController extends Controller {
  /// GET /api/notifications?page=&limit=  (authenticated)
  Future<Response> getNotifications(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final page =
        int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;

    final notifications = await NotificationModel()
        .query()
        .where('user_id', '=', authUserId)
        .orderBy('created_at', 'DESC')
        .paginate(limit, page);

    // Count unread
    final unreadCount = await NotificationModel()
        .query()
        .where('user_id', '=', authUserId)
        .where('is_read', '=', 0)
        .count();

    return Response.json({
      'notifications': notifications,
      'unread_count': unreadCount,
    }, HttpStatus.ok);
  }

  /// POST /api/notifications/read  (authenticated)
  /// Body: { ids?: [id1, id2] } - if empty, marks all as read
  Future<Response> markRead(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final ids = request.body['ids'] as List<dynamic>?;
    final now = DateTime.now().toIso8601String();

    if (ids != null && ids.isNotEmpty) {
      for (final id in ids) {
        await NotificationModel()
            .query()
            .where('id', '=', id.toString())
            .where('user_id', '=', authUserId)
            .update({'is_read': 1, 'updated_at': now});
      }
    } else {
      await NotificationModel()
          .query()
          .where('user_id', '=', authUserId)
          .update({'is_read': 1, 'updated_at': now});
    }

    return Response.json({'message': 'Notifications marked as read'}, 200);
  }
}

final NotificationController notificationController = NotificationController();
