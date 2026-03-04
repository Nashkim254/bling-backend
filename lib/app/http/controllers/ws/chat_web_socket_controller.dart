import 'package:vania/vania.dart';
import 'package:uuid/uuid.dart';

class ChatWebSocketController extends Controller {
  // Track online users: userId -> clientId
  final Map<String, String> _userToClient = {};
  // Track client to user: clientId -> userId
  final Map<String, String> _clientToUser = {};

  Function get onConnected => (WebSocketClient client) {
        print('[WS] Client connected: ${client.clientId}');
      };

  Function get onDisconnected => (WebSocketClient client) {
        final userId = _clientToUser[client.clientId];
        if (userId != null) {
          _userToClient.remove(userId);
          _clientToUser.remove(client.clientId);
          client.broadcast('user_offline', {'userId': userId});
          print('[WS] User disconnected: $userId');
        }
      };

  void connectedEventHandler(WebSocketClient client, dynamic data) {
    print('[WS] User event connected: $data');
  }

  /// Initialize session - called by client after connecting
  /// Data: { userId, token? }
  void handleInit(WebSocketClient client, dynamic data) {
    final userId = data['userId']?.toString() ?? '';
    if (userId.isEmpty) return;

    _userToClient[userId] = client.clientId;
    _clientToUser[client.clientId] = userId;

    print('[WS] User online: $userId (clientId: ${client.clientId})');

    // Emit online status to all
    client.broadcast('user_online', {'userId': userId});

    // Send current online users list to this client
    client.emit('online_users', {'users': _userToClient.keys.toList()});
  }

  /// Handle private 1-on-1 message
  /// Data: { from, to, content }
  void handlePrivateMessage(WebSocketClient client, dynamic data) async {
    final from = data['from']?.toString() ?? '';
    final to = data['to']?.toString() ?? '';
    final content = data['content']?.toString() ?? '';

    if (from.isEmpty || to.isEmpty || content.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final msgId = const Uuid().v4();
    final toClientId = _userToClient[to] ?? '';
    final isDelivered = toClientId.isNotEmpty;

    final message = {
      'id': msgId,
      'from_user_id': from,
      'to_user_id': to,
      'content': content,
      'is_read': 0,
      'delivered': isDelivered ? 1 : 0,
      'created_at': now,
    };

    // Persist to database
    try {
      await connection!.statement(
        'INSERT INTO chats (id, from_user_id, to_user_id, content, is_read, delivered, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,0,\$5,\$6,\$7)',
        [msgId, from, to, content, isDelivered ? 1 : 0, now, now],
      );
    } catch (e) {
      print('[WS] DB error saving message: $e');
    }

    // Send to recipient if online
    if (isDelivered) {
      client.to(toClientId, 'private_message', message);
    }

    // Echo back to sender with the saved message id
    client.emit('message_sent', message);
  }

  /// Handle typing status
  /// Data: { from, to, isTyping }
  void handleTypingStatus(WebSocketClient client, dynamic data) {
    final to = data['to']?.toString() ?? '';
    final toClientId = _userToClient[to] ?? '';
    if (toClientId.isEmpty) return;

    client.to(toClientId, 'typing_status', {
      'userId': data['from'],
      'isTyping': data['isTyping'],
    });
  }

  /// Fetch chat history with a user
  /// Data: { userId, partnerId, page?, limit? }
  void handleFetchChats(WebSocketClient client, dynamic data) async {
    final userId = data['userId']?.toString() ?? '';
    final partnerId = data['partnerId']?.toString() ?? '';
    final page = int.tryParse(data['page']?.toString() ?? '1') ?? 1;
    final limit = int.tryParse(data['limit']?.toString() ?? '50') ?? 50;

    if (userId.isEmpty) return;

    try {
      List<Map<String, dynamic>> messages;
      if (partnerId.isNotEmpty) {
        messages = await connection!.select(
          '''SELECT id, from_user_id, to_user_id, content, is_read, delivered, created_at
             FROM chats
             WHERE (from_user_id = \$1 AND to_user_id = \$2)
                OR (from_user_id = \$2 AND to_user_id = \$1)
             ORDER BY created_at DESC
             LIMIT \$3 OFFSET \$4''',
          [userId, partnerId, limit, (page - 1) * limit],
        );
      } else {
        messages = await connection!.select(
          '''SELECT id, from_user_id, to_user_id, content, is_read, delivered, created_at
             FROM chats
             WHERE from_user_id = \$1 OR to_user_id = \$1
             ORDER BY created_at DESC
             LIMIT \$2 OFFSET \$3''',
          [userId, limit, (page - 1) * limit],
        );
      }

      client.emit('chat_history', {
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
      });
    } catch (e) {
      print('[WS] Error fetching chats: $e');
      client.emit('chat_history', {'messages': []});
    }
  }

  /// Mark messages as read
  /// Data: { userId, fromUserId }
  void handleMarkRead(WebSocketClient client, dynamic data) async {
    final userId = data['userId']?.toString() ?? '';
    final fromUserId = data['fromUserId']?.toString() ?? '';
    if (userId.isEmpty || fromUserId.isEmpty) return;

    try {
      await connection!.statement(
        'UPDATE chats SET is_read = 1 WHERE to_user_id = \$1 AND from_user_id = \$2 AND is_read = 0',
        [userId, fromUserId],
      );

      // Notify sender that messages were read
      final senderClientId = _userToClient[fromUserId] ?? '';
      if (senderClientId.isNotEmpty) {
        client.to(senderClientId, 'messages_read', {
          'by_user_id': userId,
          'from_user_id': fromUserId,
        });
      }
    } catch (e) {
      print('[WS] Error marking read: $e');
    }
  }

  /// Handle room message (group chat)
  void handleRoomMessage(WebSocketClient client, dynamic data) {
    final roomId = data['roomId']?.toString() ?? '';
    if (roomId.isEmpty) return;

    final userId = _clientToUser[client.clientId] ?? client.clientId;
    client.toRoom('room_message', roomId, {
      'from': userId,
      'content': data['content'],
      'roomId': roomId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void handleJoinRoom(WebSocketClient client, dynamic data) {
    final roomId = data['roomId']?.toString() ?? '';
    if (roomId.isEmpty) return;
    final userId = _clientToUser[client.clientId] ?? client.clientId;
    client.toRoom('user_joined', roomId, {
      'userId': userId,
      'roomId': roomId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void handleLeaveRoom(WebSocketClient client, dynamic data) {
    final roomId = data['roomId']?.toString() ?? '';
    if (roomId.isEmpty) return;
    final userId = _clientToUser[client.clientId] ?? client.clientId;
    client.toRoom('user_left', roomId, {
      'userId': userId,
      'roomId': roomId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

ChatWebSocketController chatController = ChatWebSocketController();
