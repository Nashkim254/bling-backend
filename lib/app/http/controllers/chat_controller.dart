import 'dart:io';

import 'package:vania/vania.dart';

class ChatController extends Controller {
  /// GET /api/chats  (authenticated) - get conversation list
  Future<Response> getConversations(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    try {
      // Get unique conversation partners with last message
      final conversations = await connection!.select(
        '''SELECT DISTINCT ON (partner_id)
           partner_id,
           partner_name,
           partner_username,
           partner_avatar,
           last_message,
           last_message_time,
           unread_count
           FROM (
             SELECT
               CASE WHEN from_user_id = \$1 THEN to_user_id ELSE from_user_id END as partner_id,
               u.name as partner_name,
               u.username as partner_username,
               u.avatar as partner_avatar,
               content as last_message,
               c.created_at as last_message_time,
               SUM(CASE WHEN to_user_id = \$1 AND is_read = 0 THEN 1 ELSE 0 END) OVER (PARTITION BY CASE WHEN from_user_id = \$1 THEN to_user_id ELSE from_user_id END) as unread_count
             FROM chats c
             JOIN users u ON u.id = CASE WHEN from_user_id = \$1 THEN to_user_id ELSE from_user_id END
             WHERE from_user_id = \$1 OR to_user_id = \$1
             ORDER BY c.created_at DESC
           ) t
           ORDER BY partner_id, last_message_time DESC''',
        [authUserId],
      );

      return Response.json({
        'conversations': conversations
            .map((c) => {
                  'partner_id': c['partner_id'],
                  'partner_name': c['partner_name'],
                  'partner_username': c['partner_username'],
                  'partner_avatar': c['partner_avatar'],
                  'last_message': c['last_message'],
                  'last_message_time': c['last_message_time'].toString(),
                  'unread_count': c['unread_count'] ?? 0,
                })
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching conversations',
        'error': e.toString(),
      }, 500);
    }
  }

  /// GET /api/chats/:userId?page=&limit=  (authenticated) - get messages with user
  Future<Response> getMessages(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    final partnerId = request.params()['userId'] as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '50') ?? 50;

    try {
      final messages = await connection!.select(
        '''SELECT id, from_user_id, to_user_id, content, is_read, delivered, created_at
           FROM chats
           WHERE (from_user_id = \$1 AND to_user_id = \$2)
              OR (from_user_id = \$2 AND to_user_id = \$1)
           ORDER BY created_at DESC
           LIMIT \$3 OFFSET \$4''',
        [authUserId, partnerId, limit, (page - 1) * limit],
      );

      // Mark messages as read
      await connection!.statement(
        'UPDATE chats SET is_read = 1 WHERE to_user_id = \$1 AND from_user_id = \$2 AND is_read = 0',
        [authUserId, partnerId],
      );

      return Response.json({
        'messages': messages
            .map((m) => {
                  'id': m['id'],
                  'from_user_id': m['from_user_id'],
                  'to_user_id': m['to_user_id'],
                  'content': m['content'],
                  'is_read': m['is_read'],
                  'delivered': m['delivered'],
                  'created_at': m['created_at'].toString(),
                })
            .toList()
            .reversed
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching messages',
        'error': e.toString(),
      }, 500);
    }
  }
}

final ChatController chatController = ChatController();
