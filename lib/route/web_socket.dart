import 'package:vania/vania.dart';
import 'package:bling/app/http/controllers/ws/chat_web_socket_controller.dart';

class WebSocketRoute implements Route {
  @override
  void register() {
    Router.websocket('/ws', (WebSocketEvent event) {
      event.on('connect', chatController.onConnected);
      event.on('disconnect', chatController.onDisconnected);
      event.on('user_connected', chatController.connectedEventHandler);
      event.on('init', chatController.handleInit);
      event.on('private_message', chatController.handlePrivateMessage);
      event.on('typing_status', chatController.handleTypingStatus);
      event.on('fetch_chats', chatController.handleFetchChats);
      event.on('mark_read', chatController.handleMarkRead);
      event.on('room_message', chatController.handleRoomMessage);
      event.on('join_room', chatController.handleJoinRoom);
      event.on('leave_room', chatController.handleLeaveRoom);
    });
  }
}
