import 'package:vania/vania.dart';

class ChatWebSocketController extends Controller {
  Function get onConnected => (WebSocketClient client) {
        print('Client connected: ${client.clientId}');
        client.broadcast('user_connected', {'userId': client.clientId});
      };

  Function get onDisconnected => (WebSocketClient client) {
        print('Client disconnected: ${client.clientId}');
        client.broadcast('user_disconnected', {'userId': client.clientId});
      };

  // Handle private messages
  void handlePrivateMessage(WebSocketClient client, dynamic data) {
    print(client);
    print("Client id:${client.clientId}");
    final String toUserId = data['to'];
    client.to(toUserId, 'private_message', {
      'from': client.clientId,
      'content': data['content'],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Handle room messages
  void handleRoomMessage(WebSocketClient client, dynamic data) {
    final String roomId = data['roomId'];
    client.toRoom('room_message', roomId, {
      'from': client.clientId,
      'content': data['content'],
      'roomId': roomId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Join room
  void handleJoinRoom(WebSocketClient client, dynamic data) {
    final String roomId = data['roomId'];
    // client.joinRoom(roomId);
    client.toRoom('user_joined', roomId, {
      'userId': client.clientId,
      'roomId': roomId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Leave room
  void handleLeaveRoom(WebSocketClient client, dynamic data) {
    final String roomId = data['roomId'];
    // client.leftRoom(roomId);
    client.toRoom('user_left', roomId, {
      'userId': client.clientId,
      'roomId': roomId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Typing status
  void handleTypingStatus(WebSocketClient client, dynamic data) {
    if (data['roomId'] != null) {
      // Room typing status
      client.toRoom('typing_status', data['roomId'], {
        'userId': client.clientId,
        'isTyping': data['isTyping'],
        'roomId': data['roomId'],
      });
    } else {
      // Private typing status
      client.to(data['to'], 'typing_status', {
        'userId': client.clientId,
        'isTyping': data['isTyping'],
      });
    }
  }

  // Get room members
  void handleGetRoomMembers(WebSocketClient client, dynamic data) {
    final String roomId = data['roomId'];
    final members = client.getRoomMembers(roomId: roomId);
    client.emit('room_members', {
      'roomId': roomId,
      'members': members,
    });
  }
}

ChatWebSocketController chatController = ChatWebSocketController();
