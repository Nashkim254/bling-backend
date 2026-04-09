import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class SupportController extends Controller {
  String _authUserId(Request request) {
    final requestUserId = request.input('auth_user_id')?.toString() ?? '';
    if (requestUserId.isNotEmpty) return requestUserId;
    return Auth().id()?.toString() ?? '';
  }

  Future<Response> createRequest(Request request) async {
    final userId = _authUserId(request);
    if (userId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final body = request.body;
    final issueType = body['issue_type']?.toString().trim() ?? '';
    final feedback = body['feedback']?.toString().trim() ?? '';
    final transactionReference =
        body['transaction_reference']?.toString().trim() ?? '';

    if (!['app_malfunction', 'bling_transaction'].contains(issueType)) {
      return Response.json({'message': 'Invalid support type'}, 422);
    }
    if (feedback.isEmpty) {
      return Response.json({'message': 'Feedback is required'}, 422);
    }
    if (issueType == 'bling_transaction' && transactionReference.isEmpty) {
      return Response.json(
        {'message': 'Transaction reference is required'},
        422,
      );
    }

    final conversationId = const Uuid().v4();
    final notificationId = const Uuid().v4();
    final messageId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final subject = issueType == 'bling_transaction'
        ? 'Bling Transaction'
        : 'App Malfunction';
    final content = transactionReference.isEmpty
        ? feedback
        : '$feedback\n\nTransaction Reference: $transactionReference';

    await connection!.statement(
      '''
      INSERT INTO conversations (
        id, type, name, avatar, created_by, created_at, updated_at
      ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$6)
      ''',
      [conversationId, 'group', 'Bling_Support', '', userId, now],
    );

    await connection!.statement(
      '''
      INSERT INTO conversation_members (
        id, conversation_id, user_id, role, joined_at, created_at, updated_at
      ) VALUES (\$1, \$2, \$3, \$4, \$5, \$5, \$5)
      ''',
      [const Uuid().v4(), conversationId, userId, 'member', now],
    );

    await connection!.statement(
      '''
      INSERT INTO chats (
        id, conversation_id, from_user_id, to_user_id, content,
        message_type, is_read, delivered, is_deleted, created_at, updated_at
      ) VALUES (\$1, \$2, \$3, \$3, \$4, 'text', 0, 1, 0, \$5, \$5)
      ''',
      [messageId, conversationId, userId, content, now],
    );

    await connection!.statement(
      '''
      UPDATE conversations
      SET last_message = \$1,
          last_message_sender_id = \$2,
          last_message_at = \$3,
          updated_at = \$3
      WHERE id = \$4
      ''',
      [feedback, userId, now, conversationId],
    );

    await connection!.statement(
      '''
      INSERT INTO notifications (
        id, user_id, type, title, body, data, is_read, created_at, updated_at
      ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 0, \$7, \$7)
      ''',
      [
        notificationId,
        userId,
        'support_request',
        subject,
        feedback,
        jsonEncode({
          'conversation_id': conversationId,
          'issue_type': issueType,
          'transaction_reference': transactionReference,
        }),
        now,
      ],
    );

    return Response.json({
      'message': 'Support request sent',
      'conversation_id': conversationId,
      'conversation_name': 'Bling_Support',
      'conversation_type': 'group',
      'conversation_avatar': '',
    }, HttpStatus.ok);
  }
}

final SupportController supportController = SupportController();
