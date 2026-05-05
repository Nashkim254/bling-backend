import 'dart:convert';
import 'dart:io';

import 'package:bling/app/http/request_data.dart';
import 'package:bling/app/models/challenge_entry.dart';
import 'package:bling/app/models/challenges_model.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/bling_transaction.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class ChallengesController extends Controller {
  String _authUserId(Request request) {
    final requestUserId = request.input('auth_user_id') as String? ?? '';
    if (requestUserId.isNotEmpty) {
      return requestUserId;
    }

    return Auth().id()?.toString() ?? '';
  }

  /// GET /api/challenges?page=&limit=
  Future<Response> getChallenges(Request request) async {
    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '10') ?? 10;
    final authUserId = _authUserId(request);

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
            'challenges.entry_fee_bling',
            'challenges.judging_type',
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
            'challenges.entry_fee_bling',
            'challenges.judging_type',
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
            .whereType<Map>()
            .map((e) => e['challenge_id']?.toString() ?? '')
            .toList();
      }

      final rows = (challenges['data'] as List<dynamic>).whereType<Map>();
      final data = rows.map((ch) {
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
          'entry_fee_bling': ch['entry_fee_bling'] ?? 0,
          'judging_type': ch['judging_type'] ?? 'hybrid',
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
    final authUserId = _authUserId(request);

    try {
      final rows = await connection!.select('''
        SELECT c.id, c.user_id, c.title, c.description, c.hashtags, c.image_url, c.media::TEXT AS media,
               c.thumbnail_url, c.video_url, c.media_kind,
               c.storage_bucket, c.storage_path, c.mime_type,
               c.prize_bling, c.entry_fee_bling, c.judging_type, c.is_active, c.ends_at, c.created_at,
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
               u.name AS user_name, u.username AS user_username, u.avatar AS user_avatar,
               u.is_verified AS user_is_verified,
               p.user_id AS post_user_id, p.caption AS post_caption, p.post_type AS post_type, p.image_url AS post_image_url,
               p.thumbnail_url AS post_thumbnail_url, p.video_url AS post_video_url,
               p.media_kind AS post_media_kind, p.storage_bucket AS post_storage_bucket,
               p.storage_path AS post_storage_path, p.mime_type AS post_mime_type,
               COALESCE(p.media::TEXT, '[]') AS post_media,
               COALESCE(COUNT(DISTINCT l.id), 0) AS post_like_count,
               COALESCE(COUNT(DISTINCT c.id), 0) AS post_comment_count,
               p.is_active AS post_is_active, p.created_at AS post_created_at
        FROM challenge_entries ce
        JOIN users u ON u.id = ce.user_id
        LEFT JOIN posts p ON p.id = ce.post_id AND p.is_active = 1
        LEFT JOIN likes l ON l.post_id = p.id
        LEFT JOIN comments c ON c.post_id = p.id
        WHERE ce.challenge_id = \$1
        GROUP BY ce.id, ce.user_id, ce.post_id, ce.is_winner, ce.created_at,
                 u.name, u.username, u.avatar, u.is_verified,
                 p.user_id, p.caption, p.post_type, p.image_url,
                 p.thumbnail_url, p.video_url, p.media_kind, p.storage_bucket,
                 p.storage_path, p.mime_type, p.media::TEXT, p.is_active, p.created_at
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

      final participantRows = participants.whereType<Map>();

      final finalistIds = await _loadFinalistEntryIds(challengeId);
      final finalistRanks = <String, int>{
        for (var i = 0; i < finalistIds.length; i++) finalistIds[i]: i + 1,
      };

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
          'entry_fee_bling': ch['entry_fee_bling'] ?? 0,
          'judging_type': ch['judging_type'] ?? 'hybrid',
          'is_active': ch['is_active'],
          'ends_at': ch['ends_at']?.toString(),
          'entry_count': ch['entry_count'] ?? 0,
          'is_entered': isEntered,
          'created_at': ch['created_at'].toString(),
        },
        'participants': participantRows
            .map((p) => {
                  'id': p['id']?.toString(),
                  'user_id': p['user_id']?.toString(),
                 'user_name': p['user_name'],
                  'user_username': p['user_username'],
                  'user_avatar': p['user_avatar'],
                  'user_is_verified':
                      p['user_is_verified'] == 1 ||
                          p['user_is_verified'] == true,
                  'post_id': p['post_id']?.toString(),
                  'is_winner': p['is_winner'] == 1 || p['is_winner'] == true,
                  'joined_at': p['created_at'].toString(),
                  'is_finalist': finalistRanks.containsKey(
                    p['id']?.toString() ?? '',
                  ),
                  'finalist_rank': finalistRanks[p['id']?.toString() ?? ''],
                  'post': p['post_id'] == null
                      ? null
                      : {
                          'id': p['post_id']?.toString(),
                          'user_id': p['post_user_id']?.toString(),
                          'caption': p['post_caption'] ?? '',
                          'post_type': p['post_type']?.toString().trim(),
                          'media': _decodeMediaText(
                            p['post_media'],
                            imageUrl: p['post_image_url']?.toString() ?? '',
                            thumbnailUrl:
                                p['post_thumbnail_url']?.toString() ?? '',
                            videoUrl: p['post_video_url']?.toString() ?? '',
                            mediaKind:
                                p['post_media_kind']?.toString() ?? 'image',
                            bucket:
                                p['post_storage_bucket']?.toString() ?? '',
                            path: p['post_storage_path']?.toString() ?? '',
                            mimeType: p['post_mime_type']?.toString() ?? '',
                          ),
                          'image_url': p['post_image_url'] ?? '',
                          'thumbnail_url': p['post_thumbnail_url'] ?? '',
                          'video_url': p['post_video_url'] ?? '',
                          'media_kind': p['post_media_kind'] ?? 'image',
                          'storage_bucket': p['post_storage_bucket'] ?? '',
                          'storage_path': p['post_storage_path'] ?? '',
                          'mime_type': p['post_mime_type'] ?? '',
                          'is_active': p['post_is_active'] ?? 1,
                          'created_at': p['post_created_at']?.toString() ??
                              p['created_at'].toString(),
                          'comment_count': p['post_comment_count'] ?? 0,
                          'like_count': p['post_like_count'] ?? 0,
                          'extracted_hashtags': '[]',
                          'is_liked': false,
                          'item_type': 'post',
                        },
                })
            .toList(),
      }, 200);
    } catch (e) {
      return Response.json({'message': 'Error', 'error': e.toString()}, 500);
    }
  }

  /// POST /api/challenges  (authenticated)
  Future<Response> createChallenge(Request request) async {
    final authUserId = _authUserId(request);
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final data = RequestData(request);
    final errors = data.require({
      'title': 'Title is required',
      'description': 'Description is required',
    });
    if (errors.isNotEmpty) {
      return Response.json(errors, 422);
    }

    final challengeId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final prizeBling = data.intValue('prize_bling') ?? 0;
    final entryFeeBling = data.intValue('entry_fee_bling') ?? 0;
    final endsAt = _resolveEndsAt(data.trimmed('ends_at'));
    int deductedPrizeAmount = 0;
    int previousBalance = 0;

    try {
      final media = _normalizeMediaInput(data.value('media'));
      final legacyMedia = _legacyFieldsFromMedia(
        media,
        fallbackImageUrl: data.trimmed('image_url'),
        fallbackThumbnailUrl: data.trimmed('thumbnail_url'),
        fallbackVideoUrl: data.trimmed('video_url'),
        fallbackMediaKind: data.trimmed('media_kind', fallback: 'image'),
        fallbackBucket: data.trimmed('storage_bucket'),
        fallbackPath: data.trimmed('storage_path'),
        fallbackMimeType: data.trimmed('mime_type'),
      );

      if (prizeBling > 0) {
        final wallet =
            await Wallet().query().where('user_id', '=', authUserId).first();
        previousBalance = (wallet?['balance'] as num?)?.toInt() ?? 0;
        if (previousBalance < prizeBling) {
          return Response.json({
            'message': 'Not enough Bling to fund this prize pool',
          }, 400);
        }

        await Wallet().query().where('user_id', '=', authUserId).update({
          'balance': previousBalance - prizeBling,
          'updated_at': now,
        });
        deductedPrizeAmount = prizeBling;

        await BlingTransaction().query().insert({
          'id': const Uuid().v4(),
          'user_id': authUserId,
          'to_user_id': null,
          'type': 'challenge_prize_fund',
          'amount': prizeBling,
          'reference': challengeId,
          'description': 'Funded challenge prize pool',
          'created_at': now,
          'updated_at': now,
        });
      }

      final body = <String, dynamic>{
        'id': challengeId,
        'user_id': authUserId,
        'title': data.trimmed('title'),
        'description': data.trimmed('description'),
        'hashtags': _normalizeChallengeHashtags(data.value('hashtags')),
        'media': jsonEncode(media),
        'image_url': legacyMedia['image_url'],
        'thumbnail_url': legacyMedia['thumbnail_url'],
        'video_url': legacyMedia['video_url'],
        'media_kind': legacyMedia['media_kind'],
        'storage_bucket': legacyMedia['storage_bucket'],
        'storage_path': legacyMedia['storage_path'],
        'mime_type': legacyMedia['mime_type'],
        'prize_bling': prizeBling,
        'entry_fee_bling': entryFeeBling,
        'judging_type': 'hybrid',
        'is_active': 1,
        'ends_at': endsAt,
        'created_at': now,
        'updated_at': now,
      };

      await ChallengesModel().query().insert(body);

      return Response.json({
        'message': 'Challenge created successfully',
        'challenge_id': challengeId,
        'new_balance': ((await Wallet()
                    .query()
                    .where('user_id', '=', authUserId)
                    .first())?['balance'] as num?)
                ?.toInt() ??
            0,
      }, 201);
    } catch (e) {
      if (deductedPrizeAmount > 0) {
        await Wallet().query().where('user_id', '=', authUserId).update({
          'balance': previousBalance,
          'updated_at': DateTime.now().toIso8601String(),
        });

        await connection!.statement(
          '''
          DELETE FROM bling_transactions
          WHERE reference = \$1 AND type = 'challenge_prize_fund'
          ''',
          [challengeId],
        );
      }

      return Response.json({
        'message': 'Error creating challenge',
        'error': e.toString(),
      }, HttpStatus.internalServerError);
    }
  }

  /// POST /api/challenges/:id/participate  (authenticated)
  Future<Response> participate(Request request, [dynamic _]) async {
    final challengeId = request.params()['id'] as String? ?? '';
    final authUserId = _authUserId(request);

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
    if (_isChallengeEnded(challenge)) {
      return Response.json({'message': 'Challenge has ended'}, 400);
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
    final postId = RequestData(request).trimmed('post_id');
    if (postId.isEmpty) {
      return Response.json({'message': 'Challenge entry post is required'}, 422);
    }

    final post = await connection!.select(
      '''
      SELECT id, user_id, is_active
      FROM posts
      WHERE id = \$1
      ''',
      [postId],
    );
    if (post.isEmpty ||
        post.first['user_id']?.toString() != authUserId ||
        post.first['is_active'] != 1) {
      return Response.json({'message': 'Invalid challenge entry post'}, 422);
    }

    final entryFeeBling =
        int.tryParse(challenge['entry_fee_bling']?.toString() ?? '0') ?? 0;
    int previousBalance = 0;
    if (entryFeeBling > 0) {
      final wallet =
          await Wallet().query().where('user_id', '=', authUserId).first();
      previousBalance = (wallet?['balance'] as num?)?.toInt() ?? 0;
      if (previousBalance < entryFeeBling) {
        return Response.json({
          'message': 'Not enough Bling to submit an entry',
        }, 400);
      }

      await Wallet().query().where('user_id', '=', authUserId).update({
        'balance': previousBalance - entryFeeBling,
        'updated_at': now,
      });

      await BlingTransaction().query().insert({
        'id': const Uuid().v4(),
        'user_id': authUserId,
        'to_user_id': null,
        'type': 'challenge_entry_fee',
        'amount': entryFeeBling,
        'reference': challengeId,
        'description': 'Submitted a challenge entry',
        'created_at': now,
        'updated_at': now,
      });
    }

    try {
      await ChallengeEntry().query().insert({
        'id': entryId,
        'challenge_id': challengeId,
        'user_id': authUserId,
        'post_id': postId,
        'is_winner': 0,
        'created_at': now,
        'updated_at': now,
      });
    } catch (e) {
      if (entryFeeBling > 0) {
        await Wallet().query().where('user_id', '=', authUserId).update({
          'balance': previousBalance,
          'updated_at': now,
        });
        await connection!.statement(
          '''
          DELETE FROM bling_transactions
          WHERE user_id = \$1 AND reference = \$2 AND type = 'challenge_entry_fee'
          ''',
          [authUserId, challengeId],
        );
      }
      rethrow;
    }

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
      'message': 'Challenge entry submitted successfully',
      'entry_id': entryId,
      'new_balance': entryFeeBling > 0
          ? ((await Wallet()
                      .query()
                      .where('user_id', '=', authUserId)
                      .first())?['balance'] as num?)
                  ?.toInt() ??
              0
          : null,
    }, 201);
  }

  Future<Response> awardWinner(Request request, [dynamic _]) async {
    final challengeId = request.params()['id'] as String? ?? '';
    final authUserId = _authUserId(request);
    final entryId = RequestData(request).trimmed('entry_id');

    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }
    if (entryId.isEmpty) {
      return Response.json({'message': 'entry_id is required'}, 422);
    }

    final challenge =
        await ChallengesModel().query().where('id', '=', challengeId).first();
    if (challenge == null) {
      return Response.json({'message': 'Challenge not found'}, 404);
    }
    if (challenge['user_id']?.toString() != authUserId) {
      return Response.json({'message': 'Forbidden'}, 403);
    }
    if (!_isChallengeEnded(challenge)) {
      return Response.json({
        'message': 'Challenge must be ended before a winner is selected',
      }, 400);
    }
    if ((challenge['judging_type']?.toString() ?? 'hybrid') == 'hybrid') {
      final finalistIds = await _loadFinalistEntryIds(challengeId);
      if (!finalistIds.contains(entryId)) {
        return Response.json({
          'message': 'Winner must be selected from the finalist entries',
        }, 400);
      }
    }

    final existingWinner = await ChallengeEntry()
        .query()
        .where('challenge_id', '=', challengeId)
        .where('is_winner', '=', 1)
        .first();
    if (existingWinner != null) {
      return Response.json({'message': 'Winner already selected'}, 409);
    }

    final entry = await ChallengeEntry()
        .query()
        .where('id', '=', entryId)
        .where('challenge_id', '=', challengeId)
        .first();
    if (entry == null) {
      return Response.json({'message': 'Challenge entry not found'}, 404);
    }

    final prizeBling =
        int.tryParse(challenge['prize_bling']?.toString() ?? '0') ?? 0;
    final winnerUserId = entry['user_id']?.toString() ?? '';
    final now = DateTime.now().toIso8601String();

    await ChallengeEntry().query().where('id', '=', entryId).update({
      'is_winner': 1,
      'updated_at': now,
    });
    await ChallengesModel().query().where('id', '=', challengeId).update({
      'is_active': 0,
      'updated_at': now,
    });

    if (prizeBling > 0 && winnerUserId.isNotEmpty) {
      var wallet =
          await Wallet().query().where('user_id', '=', winnerUserId).first();
      if (wallet == null) {
        final walletId = const Uuid().v4();
        await Wallet().query().insert({
          'id': walletId,
          'user_id': winnerUserId,
          'balance': 0,
          'created_at': now,
          'updated_at': now,
        });
        wallet = {'balance': 0};
      }

      final currentBalance = (wallet['balance'] as num?)?.toInt() ?? 0;
      await Wallet().query().where('user_id', '=', winnerUserId).update({
        'balance': currentBalance + prizeBling,
        'updated_at': now,
      });

      await BlingTransaction().query().insert({
        'id': const Uuid().v4(),
        'user_id': winnerUserId,
        'to_user_id': null,
        'type': 'challenge_prize_award',
        'amount': prizeBling,
        'reference': challengeId,
        'description': 'Won a challenge prize',
        'created_at': now,
        'updated_at': now,
      });
    }

    if (winnerUserId.isNotEmpty) {
      await NotificationModel().query().insert({
        'id': const Uuid().v4(),
        'user_id': winnerUserId,
        'type': 'challenge_winner',
        'title': 'You won a challenge',
        'body': prizeBling > 0
            ? 'You won ${challenge['title']} and received $prizeBling Bling.'
            : 'You were selected as the winner of ${challenge['title']}.',
        'data': '{"challenge_id":"$challengeId","entry_id":"$entryId"}',
        'is_read': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    return Response.json({
      'message': 'Winner selected successfully',
      'winner_entry_id': entryId,
    }, 200);
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

  String _normalizeChallengeHashtags(dynamic rawHashtags) {
    if (rawHashtags == null) return jsonEncode(<String>[]);
    if (rawHashtags is String) {
      final trimmed = rawHashtags.trim();
      if (trimmed.isEmpty) return jsonEncode(<String>[]);
      if (trimmed.startsWith('[')) return trimmed;
      final tags = trimmed
          .split(RegExp(r'[\s,]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      return jsonEncode(tags);
    }
    if (rawHashtags is List) {
      return jsonEncode(
        rawHashtags
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(),
      );
    }
    return jsonEncode(<String>[]);
  }

  String _resolveEndsAt(String? rawValue) {
    final parsed = rawValue == null ? null : DateTime.tryParse(rawValue);
    return (parsed ?? DateTime.now().add(const Duration(days: 7)))
        .toIso8601String();
  }

  bool _isChallengeEnded(Map challenge) {
    final endsAt = DateTime.tryParse(challenge['ends_at']?.toString() ?? '');
    if (endsAt == null) return false;
    return DateTime.now().isAfter(endsAt);
  }

  Future<List<String>> _loadFinalistEntryIds(
    String challengeId, {
    int limit = 5,
  }) async {
    final rows = await connection!.select(
      '''
      SELECT ce.id,
             COALESCE(COUNT(DISTINCT l.id), 0) AS like_count,
             COALESCE(COUNT(DISTINCT c.id), 0) AS comment_count,
             ce.created_at
      FROM challenge_entries ce
      LEFT JOIN posts p ON p.id = ce.post_id AND p.is_active = 1
      LEFT JOIN likes l ON l.post_id = p.id
      LEFT JOIN comments c ON c.post_id = p.id
      WHERE ce.challenge_id = \$1
      GROUP BY ce.id, ce.created_at
      ORDER BY like_count DESC, comment_count DESC, ce.created_at ASC
      LIMIT \$2
      ''',
      [challengeId, limit],
    );

    return rows
        .whereType<Map>()
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }
}

final ChallengesController challengesController = ChallengesController();
