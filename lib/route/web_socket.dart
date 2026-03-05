import 'package:vania/vania.dart';
import 'package:bling/app/http/controllers/ws/chat_web_socket_controller.dart';

class WebSocketRoute implements Route {
  @override
  void register() {
    Router.websocket('/ws', (WebSocketEvent event) {
      event.on('connect', chatWebSocketController.onConnected);
      event.on('disconnect', chatWebSocketController.onDisconnected);
      event.on('user_connected', chatWebSocketController.connectedEventHandler);
      event.on('init', chatWebSocketController.handleInit);
      event.on('join_conversation', chatWebSocketController.handleJoinConversation);
      event.on('send_message', chatWebSocketController.handleSendMessage);
      event.on('typing', chatWebSocketController.handleTyping);
      event.on('react_message', chatWebSocketController.handleReactMessage);
      event.on('edit_message', chatWebSocketController.handleEditMessage);
      event.on('delete_message', chatWebSocketController.handleDeleteMessage);
      event.on('message_read', chatWebSocketController.handleMessageRead);
    });
  }
}
