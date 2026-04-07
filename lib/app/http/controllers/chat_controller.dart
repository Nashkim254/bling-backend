import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:bling/app/models/block_model.dart';
import 'package:bling/services/fcm_service.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class ChatController extends Controller {
  String _authUserId(Request request) {
    final requestUserId = request.input('auth_user_id')?.toString() ?? '';
    if (requestUserId.isNotEmpty) {
      return requestUserId;
    }

    return Auth().id()?.toString() ?? '';
  }

  // ── Conversations ────────────────────────────────────────────────────────

  /// GET /api/chats  — list all conversations for the auth user
  /// Includes DMs and groups, sorted by last_message_at DESC
  /// Pinned conversations float to top.
  Future<Response> getConversations(Request request) async {
    final me = _authUserId(request);
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    try {
      final rows = await connection!.select('''
        SELECT
          c.id, c.type, c.name, c.avatar, c.last_message, c.last_message_at,
          c.last_message_sender_id,
          cm.is_pinned, cm.is_archived,
          -- For DM: partner user info
          CASE WHEN c.type = 'dm' THEN u.id END as partner_id,
          CASE WHEN c.type = 'dm' THEN u.name END as partner_name,
          CASE WHEN c.type = 'dm' THEN u.username END as partner_username,
          CASE WHEN c.type = 'dm' THEN u.avatar END as partner_avatar,
          -- Unread count
          (SELECT COUNT(*) FROM chats m
            WHERE m.conversation_id = c.id
              AND m.from_user_id != \$1
              AND m.is_read = 0
              AND m.is_deleted = 0) as unread_count,
          -- Group member count
          (SELECT COUNT(*) FROM conversation_members cm2
            WHERE cm2.conversation_id = c.id) as member_count
        FROM conversations c
        JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = \$1
        LEFT JOIN conversation_members cm_other ON cm_other.conversation_id = c.id
          AND cm_other.user_id != \$1 AND c.type = 'dm'
        LEFT JOIN users u ON u.id::text = cm_other.user_id
        WHERE cm.is_archived = 0
        ORDER BY cm.is_pinned DESC, c.last_message_at DESC NULLS LAST
      ''', [me]);

      return Response.json({
        'conversations': rows
            .whereType<Map<String, dynamic>>()
            .map(_formatConversation)
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// GET /api/chats/archived
  Future<Response> getArchivedConversations(Request request) async {
    final me = _authUserId(request);
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    try {
      final rows = await connection!.select('''
        SELECT c.id, c.type, c.name, c.avatar, c.last_message, c.last_message_at,
          cm.is_pinned, cm.is_archived,
          CASE WHEN c.type = 'dm' THEN u.id END as partner_id,
          CASE WHEN c.type = 'dm' THEN u.name END as partner_name,
          CASE WHEN c.type = 'dm' THEN u.username END as partner_username,
          CASE WHEN c.type = 'dm' THEN u.avatar END as partner_avatar,
          0 as unread_count, 0 as member_count
        FROM conversations c
        JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = \$1
        LEFT JOIN conversation_members cm_other ON cm_other.conversation_id = c.id
          AND cm_other.user_id != \$1 AND c.type = 'dm'
        LEFT JOIN users u ON u.id::text = cm_other.user_id
        WHERE cm.is_archived = 1
        ORDER BY c.last_message_at DESC NULLS LAST
      ''', [me]);

      return Response.json({
        'conversations': rows
            .whereType<Map<String, dynamic>>()
            .map(_formatConversation)
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// POST /api/chats/create  — create DM or group conversation
  /// Body: { type: 'dm'|'group', member_ids: [...], name?, avatar? }
  Future<Response> createConversation(Request request) async {
    final me = _authUserId(request);
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final body = request.body;
    final type = body['type']?.toString() ?? 'dm';
    final rawMembers = body['member_ids'];
    final List<String> memberIds =
        rawMembers is List ? rawMembers.map((e) => e.toString()).toList() : [];

    if (memberIds.isEmpty) {
      return Response.json({'message': 'member_ids required'}, 422);
    }

    // For DM: check mutual block before creating
    if (type == 'dm' && memberIds.length == 1) {
      final partnerId = memberIds.first;
      final blocked = await BlockModel()
          .query()
          .where('user_id', '=', me)
          .where('blocked_user_id', '=', partnerId)
          .first();
      final blockedBy = await BlockModel()
          .query()
          .where('user_id', '=', partnerId)
          .where('blocked_user_id', '=', me)
          .first();
      if (blocked != null || blockedBy != null) {
        return Response.json({'message': 'Cannot message this user'}, 403);
      }
    }

    final allMembers = ({me, ...memberIds}).toList();

    final now = DateTime.now().toIso8601String();

    try {
      // For DM: check if a DM conversation already exists between the two
      if (type == 'dm' && memberIds.length == 1) {
        final partnerId = memberIds.first;
        final existing = await connection!.select('''
          SELECT c.id FROM conversations c
          JOIN conversation_members cm1 ON cm1.conversation_id = c.id AND cm1.user_id = \$1
          JOIN conversation_members cm2 ON cm2.conversation_id = c.id AND cm2.user_id = \$2
          WHERE c.type = 'dm'
          LIMIT 1
        ''', [me, partnerId]);

        final existingRows =
            existing.whereType<Map<String, dynamic>>().toList();
        if (existingRows.isNotEmpty) {
          return Response.json({
            'conversation_id': existingRows.first['id']?.toString(),
            'is_new': false,
          }, HttpStatus.ok);
        }
      }

      if (type == 'group' && body['name'] == null) {
        return Response.json({'message': 'Group name required'}, 422);
      }

      final convId = const Uuid().v4();

      await connection!.statement(
        'INSERT INTO conversations (id, type, name, avatar, created_by, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7)',
        [convId, type, body['name'], body['avatar'], me, now, now],
      );

      for (final userId in allMembers) {
        await connection!.statement(
          'INSERT INTO conversation_members (id, conversation_id, user_id, role, joined_at, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7)',
          [
            const Uuid().v4(),
            convId,
            userId,
            userId == me ? 'admin' : 'member',
            now,
            now,
            now,
          ],
        );
      }

      return Response.json({
        'conversation_id': convId,
        'is_new': true,
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// DELETE /api/chats/:id  — delete conversation (removes member entry)
  Future<Response> deleteConversation(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    await connection!.statement(
      'DELETE FROM conversation_members WHERE conversation_id = \$1 AND user_id = \$2',
      [convId, me],
    );
    return Response.json({'message': 'ok'}, 200);
  }

  /// POST /api/chats/:id/pin
  Future<Response> pinConversation(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    await connection!.statement(
      'UPDATE conversation_members SET is_pinned = 1 WHERE conversation_id = \$1 AND user_id = \$2',
      [convId, me],
    );
    return Response.json({'message': 'Pinned'}, 200);
  }

  /// POST /api/chats/:id/unpin
  Future<Response> unpinConversation(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    await connection!.statement(
      'UPDATE conversation_members SET is_pinned = 0 WHERE conversation_id = \$1 AND user_id = \$2',
      [convId, me],
    );
    return Response.json({'message': 'Unpinned'}, 200);
  }

  /// POST /api/chats/:id/archive
  Future<Response> archiveConversation(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    await connection!.statement(
      'UPDATE conversation_members SET is_archived = 1 WHERE conversation_id = \$1 AND user_id = \$2',
      [convId, me],
    );
    return Response.json({'message': 'Archived'}, 200);
  }

  /// POST /api/chats/:id/unarchive
  Future<Response> unarchiveConversation(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    await connection!.statement(
      'UPDATE conversation_members SET is_archived = 0 WHERE conversation_id = \$1 AND user_id = \$2',
      [convId, me],
    );
    return Response.json({'message': 'Unarchived'}, 200);
  }

  /// POST /api/chats/:id/read  — mark all messages in conversation as read
  Future<Response> markConversationRead(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    await connection!.statement(
      'UPDATE chats SET is_read = 1 WHERE conversation_id = \$1 AND from_user_id != \$2 AND is_read = 0',
      [convId, me],
    );
    await connection!.statement(
      'UPDATE conversation_members SET last_read_at = \$1 WHERE conversation_id = \$2 AND user_id = \$3',
      [DateTime.now().toIso8601String(), convId, me],
    );
    return Response.json({'message': 'ok'}, 200);
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  /// GET /api/chats/:id/messages?page=&limit=
  Future<Response> getMessages(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '50') ?? 50;

    try {
      final messages = await connection!.select('''
        SELECT
          m.id, m.from_user_id, m.content, m.message_type,
          m.file_url, m.file_name, m.file_size,
          m.reply_to_id, m.is_deleted, m.is_read, m.edited_at, m.created_at,
          u.name as sender_name, u.avatar as sender_avatar, u.username as sender_username,
          -- Reply-to message content
          rm.content as reply_content, rm.from_user_id as reply_sender_id,
          ru.name as reply_sender_name
        FROM chats m
        JOIN users u ON u.id::text = m.from_user_id
        LEFT JOIN chats rm ON rm.id::text = m.reply_to_id
        LEFT JOIN users ru ON ru.id::text = rm.from_user_id
        WHERE m.conversation_id = \$1
        ORDER BY m.created_at DESC
        LIMIT \$2 OFFSET \$3
      ''', [convId, limit, (page - 1) * limit]);

      // Fetch reactions for all messages
      final msgIds = messages.map((m) => "'${m['id']}'").join(',');
      List<Map<String, dynamic>> reactions = [];
      if (msgIds.isNotEmpty) {
        reactions = await connection!.select(
          'SELECT message_id, user_id, user_name, emoji FROM message_reactions WHERE message_id IN ($msgIds)',
          [],
        );
      }

      final reactionsByMsg = <String, List<Map>>{};
      for (final r in reactions) {
        final mid = r['message_id'].toString();
        reactionsByMsg.putIfAbsent(mid, () => []).add(r);
      }

      // Mark as read
      await connection!.statement(
        'UPDATE chats SET is_read = 1 WHERE conversation_id = \$1 AND from_user_id != \$2 AND is_read = 0',
        [convId, me],
      );

      final result = messages.reversed.map((m) {
        final mid = m['id'].toString();
        return {
          'id': mid,
          'conversation_id': convId,
          'from_user_id': m['from_user_id'],
          'is_mine': m['from_user_id']?.toString().trim() == me,
          'sender_name': m['sender_name'],
          'sender_username': m['sender_username'],
          'sender_avatar': m['sender_avatar'],
          'content': m['is_deleted'] == 1 ? null : m['content'],
          'message_type': m['message_type'] ?? 'text',
          'file_url': m['is_deleted'] == 1 ? null : m['file_url'],
          'file_name': m['file_name'],
          'file_size': m['file_size'],
          'reply_to_id': m['reply_to_id'],
          'reply_content': m['reply_content'],
          'reply_sender_name': m['reply_sender_name'],
          'is_deleted': m['is_deleted'] == 1,
          'is_read': m['is_read'] == 1,
          'edited_at': m['edited_at']?.toString(),
          'created_at': m['created_at'].toString(),
          'reactions': reactionsByMsg[mid] ?? [],
        };
      }).toList();

      return Response.json({'messages': result}, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// POST /api/chats/:id/messages  — send message to conversation
  /// Body: { content?, message_type?, file_url?, file_name?, file_size?, reply_to_id? }
  Future<Response> sendMessage(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final convId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final body = request.body;
    final content = body['content']?.toString() ?? '';
    final messageType = body['message_type']?.toString() ?? 'text';
    final fileUrl = body['file_url']?.toString();
    final fileName = body['file_name']?.toString();
    final fileSize = int.tryParse(body['file_size']?.toString() ?? '0') ?? 0;
    final replyToId = body['reply_to_id']?.toString();

    if (content.isEmpty && fileUrl == null) {
      return Response.json({'message': 'Content or file required'}, 422);
    }

    final now = DateTime.now().toIso8601String();
    final msgId = const Uuid().v4();

    try {
      await connection!.statement('''
        INSERT INTO chats (id, conversation_id, from_user_id, to_user_id,
          content, message_type, file_url, file_name, file_size, reply_to_id,
          is_read, delivered, is_deleted, created_at, updated_at)
        VALUES (\$1,\$2,\$3,\$3,\$4,\$5,\$6,\$7,\$8,\$9,0,1,0,\$10,\$10)
      ''', [
        msgId,
        convId,
        me,
        content,
        messageType,
        fileUrl,
        fileName,
        fileSize,
        replyToId,
        now
      ]);

      // Update conversation last_message
      await connection!.statement(
        'UPDATE conversations SET last_message = \$1, last_message_sender_id = \$2, last_message_at = \$3, updated_at = \$3 WHERE id = \$4',
        [content.isNotEmpty ? content : '📎 Attachment', me, now, convId],
      );

      // Push to all other conversation members
      unawaited(_notifyChatMembers(
        convId: convId,
        senderId: me,
        content: content.isNotEmpty ? content : '📎 Attachment',
      ));

      return Response.json(
          {'message_id': msgId, 'created_at': now}, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// DELETE /api/messages/:id  — soft delete message
  Future<Response> deleteMessage(Request request, [dynamic _]) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    final msgId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final rows = await connection!.select(
      'SELECT from_user_id, conversation_id FROM chats WHERE id = \$1 LIMIT 1',
      [msgId],
    );
    if (rows.isEmpty) return Response.json({'message': 'Not found'}, 404);
    if (rows.first['from_user_id']?.toString().trim() != me) {
      return Response.json({'message': 'Forbidden'}, 403);
    }

    await connection!.statement(
      'UPDATE chats SET is_deleted = 1, content = NULL, updated_at = \$1 WHERE id = \$2',
      [DateTime.now().toIso8601String(), msgId],
    );

    return Response.json({
      'message_id': msgId,
      'conversation_id': rows.first['conversation_id'],
    }, 200);
  }

  /// PUT /api/messages/:id  — edit message (5-min window)
  Future<Response> editMessage(Request request, [dynamic _]) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    final msgId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final newContent = request.body['content']?.toString() ?? '';
    if (newContent.isEmpty)
      return Response.json({'message': 'Content required'}, 422);

    final rows = await connection!.select(
      'SELECT from_user_id, created_at, conversation_id FROM chats WHERE id = \$1 LIMIT 1',
      [msgId],
    );
    if (rows.isEmpty) return Response.json({'message': 'Not found'}, 404);
    if (rows.first['from_user_id']?.toString().trim() != me)
      return Response.json({'message': 'Forbidden'}, 403);

    final createdAt = DateTime.tryParse(rows.first['created_at'].toString()) ??
        DateTime.now();
    if (DateTime.now().difference(createdAt).inMinutes > 5) {
      return Response.json({'message': 'Edit window expired (5 min)'}, 403);
    }

    final now = DateTime.now().toIso8601String();
    await connection!.statement(
      'UPDATE chats SET content = \$1, edited_at = \$2, updated_at = \$2 WHERE id = \$3',
      [newContent, now, msgId],
    );

    return Response.json({
      'message_id': msgId,
      'content': newContent,
      'conversation_id': rows.first['conversation_id'],
      'edited_at': now,
    }, 200);
  }

  /// POST /api/messages/:id/react  — add or remove emoji reaction (toggle)
  Future<Response> reactToMessage(Request request, [dynamic _]) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    final msgId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final emoji = request.body['emoji']?.toString() ?? '';
    if (emoji.isEmpty) return Response.json({'message': 'Emoji required'}, 422);

    // Get user name
    final userRows = await connection!.select(
      'SELECT name FROM users WHERE id::text = \$1 LIMIT 1',
      [me],
    );
    final userName = userRows.isNotEmpty ? userRows.first['name'] : '';

    // Toggle: if already reacted with this emoji, remove it
    final existing = await connection!.select(
      'SELECT id FROM message_reactions WHERE message_id = \$1 AND user_id = \$2 AND emoji = \$3 LIMIT 1',
      [msgId, me, emoji],
    );

    // Get conversation_id for WS broadcast
    final msgRows = await connection!.select(
      'SELECT conversation_id FROM chats WHERE id = \$1 LIMIT 1',
      [msgId],
    );
    final convId = msgRows.isNotEmpty ? msgRows.first['conversation_id'] : '';

    if (existing.isNotEmpty) {
      await connection!.statement(
        'DELETE FROM message_reactions WHERE message_id = \$1 AND user_id = \$2 AND emoji = \$3',
        [msgId, me, emoji],
      );
      return Response.json({
        'action': 'removed',
        'message_id': msgId,
        'conversation_id': convId,
        'emoji': emoji,
        'user_id': me,
      }, 200);
    } else {
      await connection!.statement(
        'INSERT INTO message_reactions (id, message_id, user_id, user_name, emoji, created_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6)',
        [
          const Uuid().v4(),
          msgId,
          me,
          userName,
          emoji,
          DateTime.now().toIso8601String()
        ],
      );
      return Response.json({
        'action': 'added',
        'message_id': msgId,
        'conversation_id': convId,
        'emoji': emoji,
        'user_id': me,
        'user_name': userName,
      }, 200);
    }
  }

  // ── File upload ───────────────────────────────────────────────────────────

  /// POST /api/upload  — upload a file, returns { url, file_name, file_size }
  Future<Response> uploadFile(Request request) async {
    final me = request.input('auth_user_id')?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    try {
      final base64Data = request.body['data']?.toString() ?? '';
      final originalName = request.body['file_name']?.toString() ?? 'file';
      final contentType = request.body['content_type']?.toString() ??
          'application/octet-stream';

      if (base64Data.isEmpty)
        return Response.json({'message': 'No file data'}, 422);

      final bytes = base64Decode(base64Data);
      final ext = _extFromContentType(contentType, originalName);
      final fileName = '${const Uuid().v4()}$ext';

      final uploadDir = Directory('public/uploads');
      if (!uploadDir.existsSync()) uploadDir.createSync(recursive: true);

      final file = File('${uploadDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      return Response.json({
        'url': '/uploads/$fileName',
        'file_name': originalName,
        'file_size': bytes.length,
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json(
          {'message': 'Upload failed', 'error': e.toString()}, 500);
    }
  }

  Future<void> _notifyChatMembers({
    required String convId,
    required String senderId,
    required String content,
  }) async {
    try {
      final sender = await connection!
          .select('SELECT name FROM users WHERE id = \$1', [senderId]);
      final senderName = sender.isNotEmpty
          ? sender.first['name'] as String? ?? 'Someone'
          : 'Someone';

      final members = await connection!.select(
        'SELECT user_id FROM conversation_members WHERE conversation_id = \$1 AND user_id != \$2',
        [convId, senderId],
      );
      final ids = members.map((r) => r['user_id'] as String).toList();
      if (ids.isEmpty) return;

      await FcmService.instance.sendToUsers(
        ids,
        title: senderName,
        body: content,
        data: {'type': 'chat_message', 'conversation_id': convId},
      );
    } catch (e) {
      print('[FCM] _notifyChatMembers error: \$e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _formatConversation(Map<String, dynamic> r) => {
        'id': r['id']?.toString(),
        'type': r['type'],
        'name': r['type'] == 'group' ? r['name'] : r['partner_name'],
        'avatar': r['type'] == 'group' ? r['avatar'] : r['partner_avatar'],
        'partner_id': r['partner_id'],
        'partner_name': r['partner_name'],
        'partner_username': r['partner_username'],
        'partner_avatar': r['partner_avatar'],
        'last_message': r['last_message'],
        'last_message_at': r['last_message_at']?.toString(),
        'unread_count': r['unread_count'] ?? 0,
        'member_count': r['member_count'] ?? 0,
        'is_pinned': r['is_pinned'] == 1 || r['is_pinned'] == true,
        'is_archived': r['is_archived'] == 1 || r['is_archived'] == true,
      };

  String _extFromContentType(String contentType, String name) {
    if (contentType.contains('jpeg') || contentType.contains('jpg'))
      return '.jpg';
    if (contentType.contains('png')) return '.png';
    if (contentType.contains('gif')) return '.gif';
    if (contentType.contains('pdf')) return '.pdf';
    if (contentType.contains('mp4')) return '.mp4';
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx >= 0) return name.substring(dotIdx);
    return '';
  }
}

final ChatController chatController = ChatController();
