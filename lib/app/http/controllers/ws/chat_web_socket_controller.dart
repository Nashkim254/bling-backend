import 'package:vania/vania.dart';
import 'package:vania/src/websocket/websocket_session.dart';
import 'package:uuid/uuid.dart';

class ChatWebSocketController extends Controller {
  // userId -> clientId
  final Map<String, String> _userToClient = {};
  // clientId -> userId
  final Map<String, String> _clientToUser = {};

  // toRoom() uses key '${routePath}_$roomId', routePath for /ws route is '/ws'
  static const _routePrefix = '/ws_';

  void _joinRoom(WebSocketClient client, String convId) {
    WebsocketSession().joinRoom(client.clientId, '$_routePrefix$convId');
  }

  void _toConv(WebSocketClient client, String convId, String event, dynamic data) {
    client.toRoom(event, convId, data);
  }

  Function get onConnected => (WebSocketClient client) {
        print('[WS] Client connected: ${client.clientId}');
      };

  Function get onDisconnected => (WebSocketClient client) {
        final userId = _clientToUser[client.clientId];
        if (userId != null) {
          _userToClient.remove(userId);
          _clientToUser.remove(client.clientId);
          client.broadcast('user_offline', {'userId': userId});
        }
      };

  void connectedEventHandler(WebSocketClient client, dynamic data) {}

  /// init — register user and join all their conversation rooms
  void handleInit(WebSocketClient client, dynamic data) async {
    final userId = data['userId']?.toString() ?? '';
    if (userId.isEmpty) return;

    _userToClient[userId] = client.clientId;
    _clientToUser[client.clientId] = userId;

    try {
      final rows = await connection!.select(
        'SELECT conversation_id FROM conversation_members WHERE user_id = \$1',
        [userId],
      );
      for (final row in rows) {
        final convId = row['conversation_id']?.toString() ?? '';
        if (convId.isNotEmpty) _joinRoom(client, convId);
      }
    } catch (e) {
      print('[WS] Error loading conversations on init: $e');
    }

    client.broadcast('user_online', {'userId': userId});
    client.emit('online_users', {'users': _userToClient.keys.toList()});
  }

  /// join_conversation — join a specific conversation room
  void handleJoinConversation(WebSocketClient client, dynamic data) {
    final convId = data['conversationId']?.toString() ?? '';
    if (convId.isEmpty) return;
    _joinRoom(client, convId);
    client.emit('joined_conversation', {'conversationId': convId});
  }

  /// send_message — persist and broadcast to conversation
  void handleSendMessage(WebSocketClient client, dynamic data) async {
    final userId = _clientToUser[client.clientId] ?? '';
    final convId = data['conversationId']?.toString() ?? '';
    final content = data['content']?.toString() ?? '';
    final messageType = data['messageType']?.toString() ?? 'text';
    final fileUrl = data['fileUrl']?.toString();
    final fileName = data['fileName']?.toString();
    final fileSize = int.tryParse(data['fileSize']?.toString() ?? '0') ?? 0;
    final replyToId = data['replyToId']?.toString();

    if (userId.isEmpty || convId.isEmpty) return;
    if (content.isEmpty && fileUrl == null) return;

    final now = DateTime.now().toIso8601String();
    final msgId = const Uuid().v4();

    try {
      await connection!.statement('''
        INSERT INTO chats (id, conversation_id, from_user_id, to_user_id,
          content, message_type, file_url, file_name, file_size, reply_to_id,
          is_read, delivered, is_deleted, created_at, updated_at)
        VALUES (\$1,\$2,\$3,\$3,\$4,\$5,\$6,\$7,\$8,\$9,0,1,0,\$10,\$10)
      ''', [msgId, convId, userId, content, messageType, fileUrl, fileName, fileSize, replyToId, now]);

      await connection!.statement(
        'UPDATE conversations SET last_message = \$1, last_message_sender_id = \$2, last_message_at = \$3, updated_at = \$3 WHERE id = \$4',
        [content.isNotEmpty ? content : '📎 Attachment', userId, now, convId],
      );

      final userRows = await connection!.select(
        'SELECT name, username, avatar FROM users WHERE id::text = \$1 LIMIT 1', [userId],
      );
      final senderName = userRows.isNotEmpty ? userRows.first['name'] : '';
      final senderUsername = userRows.isNotEmpty ? userRows.first['username'] : '';
      final senderAvatar = userRows.isNotEmpty ? userRows.first['avatar'] : '';

      String? replyContent;
      String? replySenderName;
      if (replyToId != null && replyToId.isNotEmpty) {
        final replyRows = await connection!.select(
          '''SELECT m.content, u.name as sender_name FROM chats m
             JOIN users u ON u.id::text = m.from_user_id
             WHERE m.id = \$1 LIMIT 1''',
          [replyToId],
        );
        if (replyRows.isNotEmpty) {
          replyContent = replyRows.first['content']?.toString();
          replySenderName = replyRows.first['sender_name']?.toString();
        }
      }

      final message = {
        'id': msgId,
        'conversation_id': convId,
        'from_user_id': userId,
        'sender_name': senderName,
        'sender_username': senderUsername,
        'sender_avatar': senderAvatar,
        'content': content,
        'message_type': messageType,
        'file_url': fileUrl,
        'file_name': fileName,
        'file_size': fileSize,
        'reply_to_id': replyToId,
        'reply_content': replyContent,
        'reply_sender_name': replySenderName,
        'is_deleted': false,
        'is_read': false,
        'reactions': [],
        'created_at': now,
      };

      _toConv(client, convId, 'new_message', message);
      client.emit('message_sent', {'message_id': msgId, 'conversation_id': convId, 'created_at': now});
    } catch (e) {
      print('[WS] Error sending message: $e');
      client.emit('message_error', {'error': e.toString()});
    }
  }

  /// typing — broadcast typing indicator
  void handleTyping(WebSocketClient client, dynamic data) {
    final userId = _clientToUser[client.clientId] ?? '';
    final convId = data['conversationId']?.toString() ?? '';
    if (userId.isEmpty || convId.isEmpty) return;

    _toConv(client, convId, 'typing_status', {
      'userId': userId,
      'conversationId': convId,
      'isTyping': data['isTyping'] ?? false,
    });
  }

  /// react_message — toggle emoji reaction
  void handleReactMessage(WebSocketClient client, dynamic data) async {
    final userId = _clientToUser[client.clientId] ?? '';
    final msgId = data['messageId']?.toString() ?? '';
    final convId = data['conversationId']?.toString() ?? '';
    final emoji = data['emoji']?.toString() ?? '';

    if (userId.isEmpty || msgId.isEmpty || emoji.isEmpty) return;

    try {
      final userRows = await connection!.select(
        'SELECT name FROM users WHERE id::text = \$1 LIMIT 1', [userId],
      );
      final userName = userRows.isNotEmpty ? userRows.first['name'] : '';

      final existing = await connection!.select(
        'SELECT id FROM message_reactions WHERE message_id = \$1 AND user_id = \$2 AND emoji = \$3 LIMIT 1',
        [msgId, userId, emoji],
      );

      String action;
      if (existing.isNotEmpty) {
        await connection!.statement(
          'DELETE FROM message_reactions WHERE message_id = \$1 AND user_id = \$2 AND emoji = \$3',
          [msgId, userId, emoji],
        );
        action = 'removed';
      } else {
        await connection!.statement(
          'INSERT INTO message_reactions (id, message_id, user_id, user_name, emoji, created_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6)',
          [const Uuid().v4(), msgId, userId, userName, emoji, DateTime.now().toIso8601String()],
        );
        action = 'added';
      }

      _toConv(client, convId, 'message_reaction', {
        'action': action,
        'message_id': msgId,
        'conversation_id': convId,
        'emoji': emoji,
        'user_id': userId,
        'user_name': userName,
      });
    } catch (e) {
      print('[WS] Error reacting: $e');
    }
  }

  /// edit_message — 5-minute edit window
  void handleEditMessage(WebSocketClient client, dynamic data) async {
    final userId = _clientToUser[client.clientId] ?? '';
    final msgId = data['messageId']?.toString() ?? '';
    final convId = data['conversationId']?.toString() ?? '';
    final newContent = data['content']?.toString() ?? '';

    if (userId.isEmpty || msgId.isEmpty || newContent.isEmpty) return;

    try {
      final rows = await connection!.select(
        'SELECT from_user_id, created_at FROM chats WHERE id = \$1 LIMIT 1', [msgId],
      );
      if (rows.isEmpty || rows.first['from_user_id'] != userId) return;

      final createdAt = DateTime.tryParse(rows.first['created_at'].toString()) ?? DateTime.now();
      if (DateTime.now().difference(createdAt).inMinutes > 5) {
        client.emit('message_error', {'error': 'Edit window expired'});
        return;
      }

      final now = DateTime.now().toIso8601String();
      await connection!.statement(
        'UPDATE chats SET content = \$1, edited_at = \$2, updated_at = \$2 WHERE id = \$3',
        [newContent, now, msgId],
      );

      _toConv(client, convId, 'message_edited', {
        'message_id': msgId,
        'conversation_id': convId,
        'content': newContent,
        'edited_at': now,
      });
    } catch (e) {
      print('[WS] Error editing message: $e');
    }
  }

  /// delete_message — soft delete
  void handleDeleteMessage(WebSocketClient client, dynamic data) async {
    final userId = _clientToUser[client.clientId] ?? '';
    final msgId = data['messageId']?.toString() ?? '';
    final convId = data['conversationId']?.toString() ?? '';

    if (userId.isEmpty || msgId.isEmpty) return;

    try {
      final rows = await connection!.select(
        'SELECT from_user_id FROM chats WHERE id = \$1 LIMIT 1', [msgId],
      );
      if (rows.isEmpty || rows.first['from_user_id'] != userId) return;

      await connection!.statement(
        'UPDATE chats SET is_deleted = 1, content = NULL, updated_at = \$1 WHERE id = \$2',
        [DateTime.now().toIso8601String(), msgId],
      );

      _toConv(client, convId, 'message_deleted', {
        'message_id': msgId,
        'conversation_id': convId,
      });
    } catch (e) {
      print('[WS] Error deleting message: $e');
    }
  }

  /// message_read — mark conversation as read
  void handleMessageRead(WebSocketClient client, dynamic data) async {
    final userId = _clientToUser[client.clientId] ?? '';
    final convId = data['conversationId']?.toString() ?? '';
    if (userId.isEmpty || convId.isEmpty) return;

    try {
      await connection!.statement(
        'UPDATE chats SET is_read = 1 WHERE conversation_id = \$1 AND from_user_id != \$2 AND is_read = 0',
        [convId, userId],
      );
      await connection!.statement(
        'UPDATE conversation_members SET last_read_at = \$1 WHERE conversation_id = \$2 AND user_id = \$3',
        [DateTime.now().toIso8601String(), convId, userId],
      );

      _toConv(client, convId, 'conversation_read', {
        'conversation_id': convId,
        'read_by': userId,
      });
    } catch (e) {
      print('[WS] Error marking read: $e');
    }
  }
}

ChatWebSocketController chatWebSocketController = ChatWebSocketController();
