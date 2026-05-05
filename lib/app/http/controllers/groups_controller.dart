import 'package:bling/app/http/request_data.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class GroupsController extends Controller {
  String _authUserId(Request request) {
    final requestUserId = request.input('auth_user_id')?.toString() ?? '';
    if (requestUserId.isNotEmpty) return requestUserId;
    return Auth().id()?.toString() ?? '';
  }

  Future<Response> getGroups(Request request) async {
    final me = _authUserId(request);
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    try {
      final rows = await connection!.select(
        '''
        SELECT
          g.id,
          g.name,
          g.description,
          g.avatar,
          g.cover_image,
          g.required_level,
          g.medals_count,
          g.discoverable_country,
          g.discoverable_area,
          g.visibility,
          g.is_active,
          g.created_by,
          g.conversation_id,
          g.created_at,
          (
            SELECT COUNT(*)
            FROM group_members gm
            WHERE TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'active'
          ) AS member_count,
          (
            SELECT COUNT(*)
            FROM group_members gm
            WHERE TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'pending'
          ) AS pending_request_count,
          CASE WHEN EXISTS(
            SELECT 1
            FROM group_members gm_me
            WHERE TRIM(gm_me.group_id) = TRIM(g.id::text)
              AND TRIM(gm_me.user_id) = TRIM(\$1)
              AND gm_me.status = 'active'
          ) THEN 1 ELSE 0 END AS is_member,
          COALESCE((
            SELECT gm_me.status
            FROM group_members gm_me
            WHERE TRIM(gm_me.group_id) = TRIM(g.id::text)
              AND TRIM(gm_me.user_id) = TRIM(\$1)
            ORDER BY gm_me.updated_at DESC NULLS LAST, gm_me.created_at DESC
            LIMIT 1
          ), 'none') AS membership_status,
          CASE WHEN TRIM(g.created_by) = TRIM(\$1) THEN 1 ELSE 0 END AS is_owner,
          (
            SELECT COALESCE(SUM(u.bling_score), 0)
            FROM group_members gm
            JOIN users u ON TRIM(u.id) = TRIM(gm.user_id)
            WHERE TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'active'
          ) AS total_bling
        FROM groups g
        WHERE g.is_active = 1
        ORDER BY member_count DESC, g.created_at DESC
        ''',
        [me],
      );

      final groups = <Map<String, dynamic>>[];
      for (final row in rows) {
        final groupId = row['id']?.toString() ?? '';
        groups.add({
          ..._formatGroupRow(row),
          'member_avatars': await _memberAvatars(groupId),
        });
      }

      return Response.json({'groups': groups}, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Future<Response> getGroup(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final groupId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);
    if (groupId.isEmpty)
      return Response.json({'message': 'Group not found'}, 404);

    try {
      final rows = await connection!.select(
        '''
        SELECT
          g.id,
          g.name,
          g.description,
          g.avatar,
          g.cover_image,
          g.required_level,
          g.medals_count,
          g.discoverable_country,
          g.discoverable_area,
          g.visibility,
          g.is_active,
          g.created_by,
          g.conversation_id,
          g.created_at,
          (
            SELECT COUNT(*)
            FROM group_members gm
            WHERE TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'active'
          ) AS member_count,
          (
            SELECT COUNT(*)
            FROM group_members gm
            WHERE TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'pending'
          ) AS pending_request_count,
          CASE WHEN EXISTS(
            SELECT 1
            FROM group_members gm_me
            WHERE TRIM(gm_me.group_id) = TRIM(g.id::text)
              AND TRIM(gm_me.user_id) = TRIM(\$1)
              AND gm_me.status = 'active'
          ) THEN 1 ELSE 0 END AS is_member,
          COALESCE((
            SELECT gm_me.status
            FROM group_members gm_me
            WHERE TRIM(gm_me.group_id) = TRIM(g.id::text)
              AND TRIM(gm_me.user_id) = TRIM(\$1)
            ORDER BY gm_me.updated_at DESC NULLS LAST, gm_me.created_at DESC
            LIMIT 1
          ), 'none') AS membership_status,
          CASE WHEN TRIM(g.created_by) = TRIM(\$1) THEN 1 ELSE 0 END AS is_owner,
          (
            SELECT COALESCE(SUM(u.bling_score), 0)
            FROM group_members gm
            JOIN users u ON TRIM(u.id) = TRIM(gm.user_id)
            WHERE TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'active'
          ) AS total_bling
        FROM groups g
        WHERE TRIM(g.id::text) = TRIM(\$2)
        LIMIT 1
        ''',
        [me, groupId],
      );

      if (rows.isEmpty) {
        return Response.json({'message': 'Group not found'}, 404);
      }

      final group = rows.first;
      final creatorRows = await connection!.select(
        '''
        SELECT id, name, username, avatar, bling_score
        FROM users
        WHERE TRIM(id) = TRIM(\$1)
        LIMIT 1
        ''',
        [group['created_by']?.toString() ?? ''],
      );
      final members = await connection!.select(
        '''
        SELECT u.id, u.name, u.username, u.avatar, gm.role, gm.joined_at
        FROM group_members gm
        JOIN users u ON TRIM(u.id) = TRIM(gm.user_id)
        WHERE TRIM(gm.group_id) = TRIM(\$1) AND gm.status = 'active'
        ORDER BY gm.joined_at ASC
        ''',
        [groupId],
      );

      return Response.json({
        'group': {
          ..._formatGroupRow(group),
          'member_avatars': await _memberAvatars(groupId),
          'creator': creatorRows.isEmpty
              ? null
              : {
                  'id': creatorRows.first['id']?.toString() ?? '',
                  'name': _cleanString(creatorRows.first['name']),
                  'username': _cleanString(creatorRows.first['username']),
                  'avatar': _cleanString(creatorRows.first['avatar']),
                  'bling_score': _toInt(creatorRows.first['bling_score']),
                },
        },
        'members': members
            .map((row) => {
                  'id': row['id']?.toString() ?? '',
                  'name': _cleanString(row['name']),
                  'username': _cleanString(row['username']),
                  'avatar': _cleanString(row['avatar']),
                  'role': _cleanString(row['role'], fallback: 'member'),
                  'joined_at': row['joined_at']?.toString() ?? '',
                })
            .toList(),
      }, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Future<Response> joinGroup(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final groupId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);
    if (groupId.isEmpty)
      return Response.json({'message': 'Group not found'}, 404);

    try {
      final groupRows = await connection!.select(
        '''
        SELECT g.id, g.name, g.required_level, g.visibility, g.conversation_id, COALESCE(u.bling_score, 0) AS my_level
        FROM groups g
        JOIN users u ON TRIM(u.id) = TRIM(\$1)
        WHERE TRIM(g.id::text) = TRIM(\$2) AND g.is_active = 1
        LIMIT 1
        ''',
        [me, groupId],
      );

      if (groupRows.isEmpty) {
        return Response.json({'message': 'Group not found'}, 404);
      }

      final group = groupRows.first;
      final requiredLevel = _toInt(group['required_level']);
      final myLevel = _toInt(group['my_level']);
      if (myLevel < requiredLevel) {
        return Response.json({
          'message': 'Your bling level is too low for this group',
        }, 403);
      }

      final existing = await connection!.select(
        '''
        SELECT id, status FROM group_members
        WHERE TRIM(group_id) = TRIM(\$1) AND TRIM(user_id) = TRIM(\$2)
        ORDER BY updated_at DESC NULLS LAST, created_at DESC
        LIMIT 1
        ''',
        [groupId, me],
      );

      if (existing.isNotEmpty) {
        final status = existing.first['status']?.toString() ?? 'active';
        if (status == 'active') {
          return Response.json({
            'message': 'Already in group',
            'conversation_id': group['conversation_id']?.toString() ?? '',
            'status': 'active',
          }, 200);
        }
        if (status == 'pending') {
          return Response.json({
            'message': 'Join request pending approval',
            'status': 'pending',
          }, 200);
        }
      }

      final visibility = group['visibility']?.toString() ?? 'public';
      final now = DateTime.now().toIso8601String();
      final memberStatus = visibility == 'private' ? 'pending' : 'active';
      await connection!.statement(
        '''
        INSERT INTO group_members (id, group_id, user_id, role, status, joined_at, created_at, updated_at)
        VALUES (\$1, \$2, \$3, 'member', \$4, \$5, \$5, \$5)
        ''',
        [const Uuid().v4(), groupId, me, memberStatus, now],
      );

      if (memberStatus == 'active') {
        final conversationId = group['conversation_id']?.toString() ?? '';
        if (conversationId.isNotEmpty) {
          final existingConversationMember = await connection!.select(
            '''
            SELECT id FROM conversation_members
            WHERE TRIM(conversation_id) = TRIM(\$1) AND TRIM(user_id) = TRIM(\$2)
            LIMIT 1
            ''',
            [conversationId, me],
          );
          if (existingConversationMember.isEmpty) {
            await connection!.statement(
              '''
              INSERT INTO conversation_members
                (id, conversation_id, user_id, role, joined_at, created_at, updated_at)
              VALUES (\$1, \$2, \$3, 'member', \$4, \$4, \$4)
              ''',
              [const Uuid().v4(), conversationId, me, now],
            );
          }
        }
      } else {
        return Response.json({
          'message': 'Join request sent',
          'status': 'pending',
        }, 200);
      }

      return Response.json({
        'message': 'Joined group',
        'conversation_id': group['conversation_id']?.toString() ?? '',
        'status': 'active',
      }, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Future<Response> leaveGroup(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final groupId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);
    if (groupId.isEmpty)
      return Response.json({'message': 'Group not found'}, 404);

    try {
      final groupRows = await connection!.select(
        'SELECT conversation_id FROM groups WHERE TRIM(id::text) = TRIM(\$1) LIMIT 1',
        [groupId],
      );
      if (groupRows.isEmpty) {
        return Response.json({'message': 'Group not found'}, 404);
      }

      await connection!.statement(
        'DELETE FROM group_members WHERE TRIM(group_id) = TRIM(\$1) AND TRIM(user_id) = TRIM(\$2)',
        [groupId, me],
      );

      final conversationId =
          groupRows.first['conversation_id']?.toString() ?? '';
      if (conversationId.isNotEmpty) {
        await connection!.statement(
          'DELETE FROM conversation_members WHERE TRIM(conversation_id) = TRIM(\$1) AND TRIM(user_id) = TRIM(\$2)',
          [conversationId, me],
        );
      }

      return Response.json({'message': 'Left group'}, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Future<Response> createGroup(Request request) async {
    final me = _authUserId(request);
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);

    final data = RequestData(request);
    final errors = data.require({
      'name': 'Group name is required',
      'description': 'Group description is required',
    });
    if (errors.isNotEmpty) {
      return Response.json(errors, 422);
    }

    final groupId = const Uuid().v4();
    final conversationId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final visibility =
        data.trimmed('visibility') == 'private' ? 'private' : 'public';
    final rawMemberIds = data.list('member_ids')
        .map((item) => item?.toString() ?? '')
        .where((item) => item.isNotEmpty && item != me)
        .toSet()
        .toList();

    try {
      await connection!.statement(
        '''
        INSERT INTO conversations (id, type, name, avatar, created_by, created_at, updated_at)
        VALUES (\$1, 'group', \$2, \$3, \$4, \$5, \$5)
        ''',
        [conversationId, data.trimmed('name'), data.trimmed('avatar'), me, now],
      );

      await connection!.statement(
        '''
        INSERT INTO conversation_members
          (id, conversation_id, user_id, role, joined_at, created_at, updated_at)
        VALUES (\$1, \$2, \$3, 'admin', \$4, \$4, \$4)
        ''',
        [const Uuid().v4(), conversationId, me, now],
      );

      await connection!.statement(
        '''
        INSERT INTO groups
          (id, name, description, avatar, cover_image, required_level, medals_count,
           visibility, is_active, created_by, conversation_id, discoverable_country,
           discoverable_area, created_at, updated_at)
        VALUES
          (\$1, \$2, \$3, \$4, \$5, \$6, 0, \$7, 1, \$8, \$9, \$10, \$11, \$12, \$12)
        ''',
        [
          groupId,
          data.trimmed('name'),
          data.trimmed('description'),
          data.trimmed('avatar'),
          data.trimmed('cover_image'),
          _toInt(data.value('required_level')),
          visibility,
          me,
          conversationId,
          data.trimmed('discoverable_country'),
          data.trimmed('discoverable_area'),
          now,
        ],
      );

      await connection!.statement(
        '''
        INSERT INTO group_members
          (id, group_id, user_id, role, status, joined_at, created_at, updated_at)
        VALUES (\$1, \$2, \$3, 'admin', 'active', \$4, \$4, \$4)
        ''',
        [const Uuid().v4(), groupId, me, now],
      );

      for (final memberId in rawMemberIds) {
        await connection!.statement(
          '''
          INSERT INTO group_members
            (id, group_id, user_id, role, status, joined_at, created_at, updated_at)
          VALUES (\$1, \$2, \$3, 'member', 'active', \$4, \$4, \$4)
          ''',
          [const Uuid().v4(), groupId, memberId, now],
        );
        await connection!.statement(
          '''
          INSERT INTO conversation_members
            (id, conversation_id, user_id, role, joined_at, created_at, updated_at)
          VALUES (\$1, \$2, \$3, 'member', \$4, \$4, \$4)
          ''',
          [const Uuid().v4(), conversationId, memberId, now],
        );
      }

      return Response.json({
        'message': 'Group created',
        'id': groupId,
        'conversation_id': conversationId,
      }, 201);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Future<Response> getGroupRequests(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final groupId = request.params()['id']?.toString() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);
    if (groupId.isEmpty) {
      return Response.json({'message': 'Group not found'}, 404);
    }

    final authorized = await _canManageGroup(groupId, me);
    if (!authorized) {
      return Response.json({'message': 'Forbidden'}, 403);
    }

    final rows = await connection!.select(
      '''
      SELECT u.id, u.name, u.username, u.avatar, u.bling_score, gm.created_at
      FROM group_members gm
      JOIN users u ON TRIM(u.id) = TRIM(gm.user_id)
      WHERE TRIM(gm.group_id) = TRIM(\$1) AND gm.status = 'pending'
      ORDER BY gm.created_at ASC
      ''',
      [groupId],
    );

    return Response.json({
      'requests': rows
          .map((row) => {
                'id': row['id']?.toString() ?? '',
                'name': _cleanString(row['name']),
                'username': _cleanString(row['username']),
                'avatar': _cleanString(row['avatar']),
                'bling_score': _toInt(row['bling_score']),
                'created_at': row['created_at']?.toString() ?? '',
              })
          .toList(),
    }, 200);
  }

  Future<Response> handleGroupRequest(Request request, [dynamic _]) async {
    final me = _authUserId(request);
    final groupId = request.params()['id']?.toString() ?? '';
    final userId = request.params()['userId']?.toString() ?? '';
    final action = request.input('action')?.toString().toLowerCase() ?? '';
    if (me.isEmpty) return Response.json({'message': 'Unauthenticated'}, 401);
    if (groupId.isEmpty || userId.isEmpty) {
      return Response.json({'message': 'Request not found'}, 404);
    }

    final authorized = await _canManageGroup(groupId, me);
    if (!authorized) {
      return Response.json({'message': 'Forbidden'}, 403);
    }
    if (action != 'approve' && action != 'reject') {
      return Response.json({'message': 'Invalid action'}, 422);
    }

    final groupRows = await connection!.select(
      '''
      SELECT conversation_id
      FROM groups
      WHERE TRIM(id::text) = TRIM(\$1)
      LIMIT 1
      ''',
      [groupId],
    );
    if (groupRows.isEmpty) {
      return Response.json({'message': 'Group not found'}, 404);
    }

    final pendingRows = await connection!.select(
      '''
      SELECT id
      FROM group_members
      WHERE TRIM(group_id) = TRIM(\$1)
        AND TRIM(user_id) = TRIM(\$2)
        AND status = 'pending'
      LIMIT 1
      ''',
      [groupId, userId],
    );
    if (pendingRows.isEmpty) {
      return Response.json({'message': 'Request not found'}, 404);
    }

    if (action == 'reject') {
      await connection!.statement(
        '''
        UPDATE group_members
        SET status = 'rejected', updated_at = NOW()
        WHERE TRIM(group_id) = TRIM(\$1)
          AND TRIM(user_id) = TRIM(\$2)
          AND status = 'pending'
        ''',
        [groupId, userId],
      );
      return Response.json({'message': 'Request rejected'}, 200);
    }

    await connection!.statement(
      '''
      UPDATE group_members
      SET status = 'active', joined_at = NOW(), updated_at = NOW()
      WHERE TRIM(group_id) = TRIM(\$1)
        AND TRIM(user_id) = TRIM(\$2)
        AND status = 'pending'
      ''',
      [groupId, userId],
    );

    final conversationId = groupRows.first['conversation_id']?.toString() ?? '';
    if (conversationId.isNotEmpty) {
      final memberRows = await connection!.select(
        '''
        SELECT id FROM conversation_members
        WHERE TRIM(conversation_id) = TRIM(\$1) AND TRIM(user_id) = TRIM(\$2)
        LIMIT 1
        ''',
        [conversationId, userId],
      );
      if (memberRows.isEmpty) {
        final now = DateTime.now().toIso8601String();
        await connection!.statement(
          '''
          INSERT INTO conversation_members
            (id, conversation_id, user_id, role, joined_at, created_at, updated_at)
          VALUES (\$1, \$2, \$3, 'member', \$4, \$4, \$4)
          ''',
          [const Uuid().v4(), conversationId, userId, now],
        );
      }
    }

    return Response.json({'message': 'Request approved'}, 200);
  }

  Future<Response> getAdminGroups(Request request) async {
    try {
      final rows = await connection!.select(
        '''
        SELECT
          g.id,
          g.name,
          g.description,
          g.avatar,
          g.cover_image,
          g.required_level,
          g.medals_count,
          g.visibility,
          g.is_active,
          g.conversation_id,
          g.created_at,
          COALESCE(COUNT(DISTINCT gm.user_id), 0) AS member_count
        FROM groups g
        LEFT JOIN group_members gm
          ON TRIM(gm.group_id) = TRIM(g.id::text) AND gm.status = 'active'
        GROUP BY g.id, g.name, g.description, g.avatar, g.cover_image, g.required_level,
                 g.medals_count, g.visibility, g.is_active, g.conversation_id, g.created_at
        ORDER BY g.created_at DESC
        ''',
        [],
      );

      final groups = <Map<String, dynamic>>[];
      for (final row in rows) {
        final groupId = row['id']?.toString() ?? '';
        groups.add({
          ..._formatGroupRow(row),
          'member_avatars': await _memberAvatars(groupId),
        });
      }

      return Response.json({'groups': groups}, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Future<Response> createAdminGroup(Request request) async {
    final adminId = request.input('auth_admin_id')?.toString() ?? '';
    if (adminId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final data = RequestData(request);
    final errors = data.require({
      'name': 'Group name is required',
      'description': 'Description is required',
    });
    if (errors.isNotEmpty) {
      return Response.json(errors, 422);
    }
    final groupId = const Uuid().v4();
    final conversationId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    try {
      await connection!.statement(
        '''
        INSERT INTO conversations (id, type, name, avatar, created_by, created_at, updated_at)
        VALUES (\$1, 'group', \$2, \$3, \$4, \$5, \$5)
        ''',
        [conversationId, data.trimmed('name'), data.trimmed('avatar'), adminId, now],
      );

      await connection!.statement(
        '''
        INSERT INTO conversation_members
          (id, conversation_id, user_id, role, joined_at, created_at, updated_at)
        VALUES (\$1, \$2, \$3, 'admin', \$4, \$4, \$4)
        ''',
        [const Uuid().v4(), conversationId, adminId, now],
      );

      await connection!.statement(
        '''
        INSERT INTO groups
          (id, name, description, avatar, cover_image, required_level, medals_count,
           visibility, is_active, created_by, conversation_id, created_at, updated_at)
        VALUES
          (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, 1, \$9, \$10, \$11, \$11)
        ''',
        [
          groupId,
          data.trimmed('name'),
          data.trimmed('description'),
          data.trimmed('avatar'),
          data.trimmed('cover_image'),
          _toInt(data.value('required_level')),
          _toInt(data.value('medals_count')),
          data.trimmed('visibility', fallback: 'public'),
          adminId,
          conversationId,
          now,
        ],
      );

      await connection!.statement(
        '''
        INSERT INTO group_members
          (id, group_id, user_id, role, status, joined_at, created_at, updated_at)
        VALUES (\$1, \$2, \$3, 'admin', 'active', \$4, \$4, \$4)
        ''',
        [const Uuid().v4(), groupId, adminId, now],
      );

      return Response.json({
        'message': 'Group created',
        'id': groupId,
        'conversation_id': conversationId,
      }, 201);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Future<Response> updateAdminGroup(Request request, [dynamic _]) async {
    final groupId = request.params()['id']?.toString() ?? '';
    if (groupId.isEmpty) {
      return Response.json({'message': 'Group not found'}, 404);
    }

    final data = RequestData(request);

    try {
      final rows = await connection!.select(
        'SELECT conversation_id FROM groups WHERE TRIM(id::text) = TRIM(\$1) LIMIT 1',
        [groupId],
      );
      if (rows.isEmpty) {
        return Response.json({'message': 'Group not found'}, 404);
      }

      await connection!.statement(
        '''
        UPDATE groups
        SET name = COALESCE(\$2, name),
            description = COALESCE(\$3, description),
            avatar = COALESCE(\$4, avatar),
            cover_image = COALESCE(\$5, cover_image),
            required_level = COALESCE(\$6, required_level),
            medals_count = COALESCE(\$7, medals_count),
            visibility = COALESCE(\$8, visibility),
            is_active = COALESCE(\$9, is_active),
            updated_at = NOW()
        WHERE TRIM(id::text) = TRIM(\$1)
        ''',
        [
          groupId,
          data.value('name'),
          data.value('description'),
          data.value('avatar'),
          data.value('cover_image'),
          data.value('required_level') == null
              ? null
              : _toInt(data.value('required_level')),
          data.value('medals_count') == null
              ? null
              : _toInt(data.value('medals_count')),
          data.value('visibility'),
          data.value('is_active') == null
              ? null
              : (data.boolValue('is_active') ? 1 : 0),
        ],
      );

      final conversationId = rows.first['conversation_id']?.toString() ?? '';
      if (conversationId.isNotEmpty) {
        await connection!.statement(
          '''
          UPDATE conversations
          SET name = COALESCE(\$2, name),
              avatar = COALESCE(\$3, avatar),
              updated_at = NOW()
          WHERE TRIM(id::text) = TRIM(\$1)
          ''',
          [conversationId, body['name'], body['avatar']],
        );
      }

      return Response.json({'message': 'Group updated'}, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  Map<String, dynamic> _formatGroupRow(Map<String, dynamic> row) {
    final requiredLevel = _toInt(row['required_level']);
    return {
      'id': row['id']?.toString() ?? '',
      'name': _cleanString(row['name']),
      'description': _cleanString(row['description']),
      'avatar': _cleanString(row['avatar']),
      'cover_image': _cleanString(row['cover_image']),
      'required_level': requiredLevel,
      'required_level_label':
          requiredLevel <= 0 ? 'All Levels' : 'Above Level $requiredLevel',
      'medals_count': _toInt(row['medals_count']),
      'discoverable_country': _cleanString(row['discoverable_country']),
      'discoverable_area': _cleanString(row['discoverable_area']),
      'visibility': _cleanString(row['visibility'], fallback: 'public'),
      'is_active': _toInt(row['is_active']) == 1,
      'created_by': _cleanString(row['created_by']),
      'conversation_id': _cleanString(row['conversation_id']),
      'member_count': _toInt(row['member_count']),
      'is_member': _toInt(row['is_member']) == 1,
      'is_owner': _toInt(row['is_owner']) == 1,
      'pending_request_count': _toInt(row['pending_request_count']),
      'membership_status':
          _cleanString(row['membership_status'], fallback: 'none'),
      'total_bling': _toInt(row['total_bling']),
      'created_at': row['created_at']?.toString() ?? '',
    };
  }

  Future<List<Map<String, dynamic>>> _memberAvatars(String groupId) async {
    final rows = await connection!.select(
      '''
      SELECT u.id, u.name, u.avatar
      FROM group_members gm
      JOIN users u ON TRIM(u.id) = TRIM(gm.user_id)
      WHERE TRIM(gm.group_id) = TRIM(\$1) AND gm.status = 'active'
      ORDER BY gm.joined_at ASC
      LIMIT 5
      ''',
      [groupId],
    );

    return rows
        .map((row) => {
              'id': row['id']?.toString() ?? '',
              'name': _cleanString(row['name']),
              'avatar': _cleanString(row['avatar']),
            })
        .toList();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  String _cleanString(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Future<bool> _canManageGroup(String groupId, String userId) async {
    final rows = await connection!.select(
      '''
      SELECT g.id
      FROM groups g
      LEFT JOIN group_members gm
        ON TRIM(gm.group_id) = TRIM(g.id::text)
       AND TRIM(gm.user_id) = TRIM(\$2)
       AND gm.status = 'active'
      WHERE TRIM(g.id::text) = TRIM(\$1)
        AND (
          TRIM(g.created_by) = TRIM(\$2)
          OR gm.role = 'admin'
        )
      LIMIT 1
      ''',
      [groupId, userId],
    );

    return rows.isNotEmpty;
  }
}

final GroupsController groupsController = GroupsController();
