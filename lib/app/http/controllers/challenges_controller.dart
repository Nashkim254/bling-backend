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
              'COALESCE(COUNT(DISTINCT challenge_entries.id), 0) AS entry_count')
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
          'image_url': ch['image_url'],
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
      final body = Map<String, dynamic>.from(request.body);
      body.remove('auth_user_id');
      final challengeId = const Uuid().v4();
      final now = DateTime.now().toIso8601String();

      body['id'] = challengeId;
      body['user_id'] = authUserId;
      body['is_active'] = 1;
      body['created_at'] = now;
      body['updated_at'] = now;

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
  Future<Response> participate(Request request) async {
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
}

final ChallengesController challengesController = ChallengesController();
