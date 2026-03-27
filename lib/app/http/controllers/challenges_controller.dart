import 'dart:convert';
import 'dart:io';

import 'package:bling/app/models/challenge_entry.dart';
import 'package:bling/app/models/challenges_model.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/user.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class ChallengesController extends Controller {
  /// GET /api/challenges?page=&limit=
  Future<Response> getChallenges(Request request) async {
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '10') ?? 10;
    final authUserId = request.input('auth_user_id') as String? ?? '';

    try {
      final challenges = await ChallengesModel()
          .query()
          .select([
            'challenges.id',
            'challenges.user_id',
            'challenges.title',
            'challenges.description',
            'challenges.hashtags',
            'challenges.image_url',
            'challenges.thumbnail_url',
            'challenges.video_url',
            'challenges.media_kind',
            'challenges.storage_bucket',
            'challenges.storage_path',
            'challenges.mime_type',
            'challenges.prize_bling',
            'challenges.is_active',
            'challenges.ends_at',
            'challenges.created_at',
            'users.name as user_name',
            'users.username as user_username',
            'users.avatar as user_avatar',
            'users.is_verified as user_is_verified',
          ])
          .selectRaw(
              'COALESCE(COUNT(DISTINCT challenge_entries.id), 0) AS entry_count, '
              "COALESCE(MIN(challenges.media::TEXT), '[]') AS media")
          .leftJoin('users', 'users.id', '=', 'challenges.user_id')
          .leftJoin('challenge_entries', 'challenge_entries.challenge_id', '=',
              'challenges.id')
          .where('challenges.is_active', '=', 1)
          .groupBy([
            'challenges.id',
            'challenges.user_id',
            'challenges.title',
            'challenges.description',
            'challenges.hashtags',
            'challenges.image_url',
            'challenges.thumbnail_url',
            'challenges.video_url',
            'challenges.media_kind',
            'challenges.storage_bucket',
            'challenges.storage_path',
            'challenges.mime_type',
            'challenges.prize_bling',
            'challenges.is_active',
            'challenges.ends_at',
            'challenges.created_at',
            'users.name',
            'users.username',
            'users.avatar',
            'users.is_verified',
          ])
          .orderBy('challenges.created_at', 'DESC')
          .paginate(limit, page);

      // Check which the auth user has favorited / entered
      List<String> enteredChallengeIds = [];
      if (authUserId.isNotEmpty) {
        final entries = await ChallengeEntry()
            .query()
            .where('user_id', '=', authUserId)
            .get();
        enteredChallengeIds = (entries as List)
            .map((e) => e['challenge_id']?.toString() ?? '')
            .toList();
      }

      final data = (challenges['data'] as List<dynamic>).map((ch) {
        return {
          'id': ch['id'],
          'user_id': ch['user_id'],
          'user_name': ch['user_name'],
          'user_username': ch['user_username'],
          'user_avatar': ch['user_avatar'],
          'user_is_verified': ch['user_is_verified'],
          'title': ch['title'],
          'description': ch['description'],
          'hashtags': ch['hashtags'],
          'media': _decodeMediaText(
            ch['media'],
            imageUrl: ch['image_url']?.toString() ?? '',
            thumbnailUrl: ch['thumbnail_url']?.toString() ?? '',
            videoUrl: ch['video_url']?.toString() ?? '',
            mediaKind: ch['media_kind']?.toString() ?? 'image',
            bucket: ch['storage_bucket']?.toString() ?? '',
            path: ch['storage_path']?.toString() ?? '',
            mimeType: ch['mime_type']?.toString() ?? '',
          ),
          'image_url': ch['image_url'],
          'thumbnail_url': ch['thumbnail_url'] ?? '',
          'video_url': ch['video_url'] ?? '',
          'media_kind': ch['media_kind'] ?? 'image',
          'storage_bucket': ch['storage_bucket'] ?? '',
          'storage_path': ch['storage_path'] ?? '',
          'mime_type': ch['mime_type'] ?? '',
          'prize_bling': ch['prize_bling'],
          'is_active': ch['is_active'],
          'ends_at': ch['ends_at']?.toString(),
          'entry_count': ch['entry_count'] ?? 0,
          'is_entered': enteredChallengeIds.contains(ch['id']?.toString()),
          'created_at': ch['created_at'].toString(),
        };
      }).toList();

      return Response.json({
        'challenges': {
          'total': challenges['total'],
          'per_page': challenges['perPage'],
          'page': challenges['page'],
          'last_page': challenges['lastPage'],
          'data': data,
        }
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Error fetching challenges',
        'error': e.toString(),
      }, HttpStatus.internalServerError);
    }
  }

  /// GET /api/challenges/:id  — single challenge with participants
  Future<Response> getChallenge(Request request, [dynamic _]) async {
    final challengeId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    try {
      final rows = await connection!.select('''
        SELECT c.id, c.user_id, c.title, c.description, c.hashtags, c.image_url, c.media::TEXT AS media,
               c.thumbnail_url, c.video_url, c.media_kind,
               c.storage_bucket, c.storage_path, c.mime_type,
               c.prize_bling, c.is_active, c.ends_at, c.created_at,
               u.name AS user_name, u.username AS user_username,
               u.avatar AS user_avatar, u.is_verified AS user_is_verified,
               COALESCE((SELECT COUNT(*) FROM challenge_entries ce
                         WHERE ce.challenge_id = c.id::text), 0) AS entry_count
        FROM challenges c
        JOIN users u ON u.id = c.user_id
        WHERE c.id::text = \$1
      ''', [challengeId]);

      if (rows.isEmpty) return Response.json({'message': 'Not found'}, 404);

      final ch = rows.first;

      final participants = await connection!.select('''
        SELECT ce.id, ce.user_id, ce.post_id, ce.is_winner, ce.created_at,
               u.name AS user_name, u.username AS user_username, u.avatar AS user_avatar
        FROM challenge_entries ce
        JOIN users u ON u.id = ce.user_id
        WHERE ce.challenge_id = \$1
        ORDER BY ce.created_at DESC
      ''', [challengeId]);

      bool isEntered = false;
      if (authUserId.isNotEmpty) {
        final entry = await ChallengeEntry()
            .query()
            .where('challenge_id', '=', challengeId)
            .where('user_id', '=', authUserId)
            .first();
        isEntered = entry != null;
      }

      return Response.json({
        'challenge': {
          'id': ch['id']?.toString(),
          'user_id': ch['user_id']?.toString(),
          'user_name': ch['user_name'],
          'user_username': ch['user_username'],
          'user_avatar': ch['user_avatar'],
          'user_is_verified': ch['user_is_verified'],
          'title': ch['title'],
          'description': ch['description'],
          'hashtags': ch['hashtags'],
          'media': _decodeMediaText(
            ch['media'],
            imageUrl: ch['image_url']?.toString() ?? '',
            thumbnailUrl: ch['thumbnail_url']?.toString() ?? '',
            videoUrl: ch['video_url']?.toString() ?? '',
            mediaKind: ch['media_kind']?.toString() ?? 'image',
            bucket: ch['storage_bucket']?.toString() ?? '',
            path: ch['storage_path']?.toString() ?? '',
            mimeType: ch['mime_type']?.toString() ?? '',
          ),
          'image_url': ch['image_url'],
          'thumbnail_url': ch['thumbnail_url'] ?? '',
          'video_url': ch['video_url'] ?? '',
          'media_kind': ch['media_kind'] ?? 'image',
          'storage_bucket': ch['storage_bucket'] ?? '',
          'storage_path': ch['storage_path'] ?? '',
          'mime_type': ch['mime_type'] ?? '',
          'prize_bling': ch['prize_bling'],
          'is_active': ch['is_active'],
          'ends_at': ch['ends_at']?.toString(),
          'entry_count': ch['entry_count'] ?? 0,
          'is_entered': isEntered,
          'created_at': ch['created_at'].toString(),
        },
        'participants': participants
            .map((p) => {
                  'id': p['id']?.toString(),
                  'user_id': p['user_id']?.toString(),
                  'user_name': p['user_name'],
                  'user_username': p['user_username'],
                  'user_avatar': p['user_avatar'],
                  'post_id': p['post_id']?.toString(),
                  'is_winner': p['is_winner'] == 1 || p['is_winner'] == true,
                  'joined_at': p['created_at'].toString(),
                })
            .toList(),
      }, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// POST /api/challenges  (authenticated)
  Future<Response> createChallenge(Request request) async {
    request.validate({
      'title': 'required|string',
      'description': 'required|string',
    }, {
      'title.required': 'Title is required',
      'description.required': 'Description is required',
    });

    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    try {
      final media = _normalizeMediaInput(request.body['media']);
      final legacyMedia = _legacyFieldsFromMedia(
        media,
        fallbackImageUrl: request.body['image_url']?.toString() ?? '',
        fallbackThumbnailUrl: request.body['thumbnail_url']?.toString() ?? '',
        fallbackVideoUrl: request.body['video_url']?.toString() ?? '',
        fallbackMediaKind: request.body['media_kind']?.toString() ?? 'image',
        fallbackBucket: request.body['storage_bucket']?.toString() ?? '',
        fallbackPath: request.body['storage_path']?.toString() ?? '',
        fallbackMimeType: request.body['mime_type']?.toString() ?? '',
      );
      final challengeId = const Uuid().v4();
      final now = DateTime.now().toIso8601String();

      final body = <String, dynamic>{
        'id': challengeId,
        'user_id': authUserId,
        'title': request.body['title']?.toString().trim() ?? '',
        'description': request.body['description']?.toString().trim() ?? '',
        'hashtags': request.body['hashtags']?.toString() ?? '',
        'media': media,
        'image_url': legacyMedia['image_url'],
        'thumbnail_url': legacyMedia['thumbnail_url'],
        'video_url': legacyMedia['video_url'],
        'media_kind': legacyMedia['media_kind'],
        'storage_bucket': legacyMedia['storage_bucket'],
        'storage_path': legacyMedia['storage_path'],
        'mime_type': legacyMedia['mime_type'],
        'prize_bling':
            int.tryParse(request.body['prize_bling']?.toString() ?? '0') ?? 0,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      };

      await ChallengesModel().query().insert(body);

      return Response.json({
        'message': 'Challenge created successfully',
        'challenge_id': challengeId,
      }, 201);
    } catch (e) {
      return Response.json({
        'message': 'Error creating challenge',
        'error': e.toString(),
      }, HttpStatus.internalServerError);
    }
  }

  /// POST /api/challenges/:id/participate  (authenticated)
  Future<Response> participate(Request request, [dynamic _]) async {
    final challengeId = request.params()['id'] as String? ?? '';
    final authUserId = request.input('auth_user_id') as String? ?? '';

    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final challenge =
        await ChallengesModel().query().where('id', '=', challengeId).first();
    if (challenge == null) {
      return Response.json({'message': 'Challenge not found'}, 404);
    }
    if (challenge['is_active'] == 0) {
      return Response.json({'message': 'Challenge is no longer active'}, 400);
    }

    // Check if already entered
    final existing = await ChallengeEntry()
        .query()
        .where('challenge_id', '=', challengeId)
        .where('user_id', '=', authUserId)
        .first();
    if (existing != null) {
      return Response.json({'message': 'Already participating'}, 409);
    }

    final now = DateTime.now().toIso8601String();
    final entryId = const Uuid().v4();
    final postId = request.body['post_id'] as String?;

    await ChallengeEntry().query().insert({
      'id': entryId,
      'challenge_id': challengeId,
      'user_id': authUserId,
      'post_id': postId,
      'is_winner': 0,
      'created_at': now,
      'updated_at': now,
    });

    // Notify challenge creator
    if (challenge['user_id'] != authUserId) {
      final participant =
          await User().query().where('id', '=', authUserId).first();
      await NotificationModel().query().insert({
        'id': const Uuid().v4(),
        'user_id': challenge['user_id'],
        'type': 'challenge_entry',
        'title': 'New Challenge Entry',
        'body':
            '${participant?['name'] ?? 'Someone'} joined your challenge: ${challenge['title']}',
        'data': '{"challenge_id":"$challengeId","user_id":"$authUserId"}',
        'is_read': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    return Response.json({
      'message': 'Joined challenge successfully',
      'entry_id': entryId,
    }, 201);
  }

  List<Map<String, dynamic>> _normalizeMediaInput(dynamic rawMedia) {
    if (rawMedia is! List) return [];

    return rawMedia
        .whereType<Map>()
        .map((entry) =>
            entry.map((key, value) => MapEntry(key.toString(), value)))
        .map((media) {
          final kind = media['kind']?.toString().trim().isNotEmpty == true
              ? media['kind'].toString().trim()
              : media['media_kind']?.toString().trim() ?? 'image';
          final url = media['url']?.toString().trim().isNotEmpty == true
              ? media['url'].toString().trim()
              : media['media_url']?.toString().trim() ?? '';
          final thumbnailUrl =
              media['thumbnail_url']?.toString().trim().isNotEmpty == true
                  ? media['thumbnail_url'].toString().trim()
                  : (kind == 'image' ? url : '');

          return {
            'kind': kind,
            'url': url,
            'thumbnail_url': thumbnailUrl,
            'storage_bucket': media['storage_bucket']?.toString() ??
                media['bucket']?.toString() ??
                '',
            'storage_path': media['storage_path']?.toString() ??
                media['path']?.toString() ??
                '',
            'mime_type': media['mime_type']?.toString() ??
                media['mimeType']?.toString() ??
                '',
            'file_name': media['file_name']?.toString() ??
                media['fileName']?.toString() ??
                '',
          };
        })
        .where((media) => (media['url']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  Map<String, String> _legacyFieldsFromMedia(
    List<Map<String, dynamic>> media, {
    required String fallbackImageUrl,
    required String fallbackThumbnailUrl,
    required String fallbackVideoUrl,
    required String fallbackMediaKind,
    required String fallbackBucket,
    required String fallbackPath,
    required String fallbackMimeType,
  }) {
    if (media.isEmpty) {
      return {
        'image_url': fallbackImageUrl,
        'thumbnail_url': fallbackThumbnailUrl,
        'video_url': fallbackVideoUrl,
        'media_kind': fallbackMediaKind,
        'storage_bucket': fallbackBucket,
        'storage_path': fallbackPath,
        'mime_type': fallbackMimeType,
      };
    }

    final primary = media.first;
    final kind = primary['kind']?.toString() ?? 'image';
    final url = primary['url']?.toString() ?? '';
    final thumbnail = primary['thumbnail_url']?.toString() ?? '';

    return {
      'image_url': kind == 'image' ? url : '',
      'thumbnail_url':
          thumbnail.isNotEmpty ? thumbnail : (kind == 'image' ? url : ''),
      'video_url': kind == 'video' ? url : '',
      'media_kind': kind,
      'storage_bucket': primary['storage_bucket']?.toString() ?? '',
      'storage_path': primary['storage_path']?.toString() ?? '',
      'mime_type': primary['mime_type']?.toString() ?? '',
    };
  }

  List<Map<String, dynamic>> _decodeMediaText(
    dynamic rawText, {
    required String imageUrl,
    required String thumbnailUrl,
    required String videoUrl,
    required String mediaKind,
    required String bucket,
    required String path,
    required String mimeType,
  }) {
    if (rawText is String && rawText.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawText);
        final normalized = _normalizeMediaInput(decoded);
        if (normalized.isNotEmpty) return normalized;
      } catch (_) {}
    }

    final fallbackUrl = mediaKind == 'video' ? videoUrl : imageUrl;
    if (fallbackUrl.isEmpty) return [];

    return [
      {
        'kind': mediaKind,
        'url': fallbackUrl,
        'thumbnail_url': thumbnailUrl.isNotEmpty
            ? thumbnailUrl
            : (mediaKind == 'image' ? imageUrl : ''),
        'storage_bucket': bucket,
        'storage_path': path,
        'mime_type': mimeType,
      }
    ];
  }
}

final ChallengesController challengesController = ChallengesController();
