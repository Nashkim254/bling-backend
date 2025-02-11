import 'package:bling/app/models/chats.dart';
import 'package:vania/vania.dart';

class ChatWebSocketController extends Controller {
  Set<String> onlineUsers = {};
  Map<String, String> clientIdToUserId = {};

  Function get onConnected => (WebSocketClient client) {
        print('client.clientId = >');
        onlineUsers.add(client.clientId);
        client.broadcast('user_connected', {'userId': client.clientId});
      };

  Function get onDisconnected => (WebSocketClient client) {
        onlineUsers.remove(client.clientId);
        clientIdToUserId.remove(client.clientId);
        client.broadcast('user_disconnected', {'userId': client.clientId});
      };
  void connectedEventHandler(WebSocketClient client, dynamic data) {
    print('Connected');
    print(data);
  }

  void handleInit(WebSocketClient client, dynamic data) {
    final String persistentUserId = data['userId'] ?? '';
    if (persistentUserId.isNotEmpty) {
      clientIdToUserId[persistentUserId] = client.clientId;
      onlineUsers.add(persistentUserId);
      print('User connected (via init): $persistentUserId (clientId: ${client.clientId})');
    } else {
      print('No userId provided in init for client: ${client.clientId}');
    }
  }

  // Handle private messages
  void handlePrivateMessage(WebSocketClient client, dynamic data) async {
    final String to = data['to'];
    final String toUserId = clientIdToUserId[to] ?? '';

    print(data);
    final privateMessage = {
      'from': data['from'],
      'to': to,
      'is_read': 0,
      'delivered': onlineUsers.contains(client.clientId),
      'content': data['content'],
      'timestamp': DateTime.now().toIso8601String(),
    };
    print('onlineUsers');
    print(onlineUsers);
    await Chats().query().insert(privateMessage);
    print('to userId: $toUserId');
    client.to(toUserId, 'private_message', privateMessage);
  }

//Handle fetch chats
  void handleFetchChats(WebSocketClient client, dynamic data) async {
    final String userId = data['userId'];
    var limit = data['limit'];
    var page = data['page'];
    final chats =
        await Chats().query().where('from', '=', userId).orderBy('timestamp').paginate(limit, page);
    client.emit('chat_history', {'chats': chats});
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
