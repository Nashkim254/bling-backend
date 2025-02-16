import 'package:vania/vania.dart';
import 'package:bling/app/http/controllers/ws/chat_web_socket_controller.dart';

class WebSocketRoute implements Route {
  @override
  void register() {
    Router.websocket('/ws', (WebSocketEvent event) {
      event.on('private_message', chatController.handlePrivateMessage);
      event.on('typing_status', chatController.handleTypingStatus);
      event.on('fetch_chats', chatController.handleFetchChats);
      // event.on('connect', chatController.onConnected);
      event.on('connect', chatController.onConnected);
      event.on('user_connected', chatController.connectedEventHandler);
      event.on('discconnect', chatController.onDisconnected);
      event.on('init', chatController.handleInit);
    });
  }
}
