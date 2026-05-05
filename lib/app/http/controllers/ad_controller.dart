import 'dart:io';

import 'package:bling/app/http/request_data.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class AdController extends Controller {
  // ─── Serving ─────────────────────────────────────────────────────────────

  /// GET /api/ads?count=1&user_level=1&is_verified=false
  ///
  /// Weighted scoring:
  ///   40% — budget remaining ratio      (more budget left = more exposure)
  ///   30% — recency boost               (newer campaigns surface faster)
  ///   30% — CTR                         (higher engagement = rewarded)
  ///
  /// Frequency cap: 1 impression per user per ad per day.
  Future<Response> getAds(Request request) async {
    final count = int.tryParse(request.input('count')?.toString() ?? '1') ?? 1;
    final userId = request.input('auth_user_id')?.toString() ?? '';
    final userLevel =
        int.tryParse(request.input('user_level')?.toString() ?? '1') ?? 1;
    final isVerified = request.input('is_verified')?.toString() == 'true';

    try {
      final userClause = userId.isNotEmpty
          ? "AND NOT EXISTS (SELECT 1 FROM ad_impressions ai WHERE ai.ad_id = a.id AND ai.user_id = '$userId' AND ai.created_at::date = CURRENT_DATE)"
          : '';

      final verifiedClause = isVerified
          ? ''
          : 'AND (a.target_verified_only = false OR a.target_verified_only IS NULL)';

      final levelClause =
          'AND (a.target_min_level IS NULL OR a.target_min_level <= $userLevel)';

      final ads = await connection!.select('''
        SELECT
          a.id, a.title, a.body, a.image_url, a.thumbnail_url, a.video_url,
          a.media_kind, a.storage_bucket, a.storage_path, a.mime_type, a.target_url,
          a.cpm_bling, a.budget_bling, a.spent_bling,
          a.total_impressions, a.total_clicks,
          -- Weighted score
          (
            COALESCE((a.budget_bling - a.spent_bling)::float / NULLIF(a.budget_bling, 0), 0) * 0.4
            + (1.0 / GREATEST(1.0, EXTRACT(EPOCH FROM (NOW() - a.created_at)) / 86400)) * 0.3
            + COALESCE(a.total_clicks::float / NULLIF(a.total_impressions, 0), 0) * 0.3
          ) AS score
        FROM ads a
        WHERE a.status = 'active'
          AND a.is_active = 1
          AND a.spent_bling < a.budget_bling
          AND (a.start_at IS NULL OR a.start_at <= NOW())
          AND (a.end_at IS NULL OR a.end_at >= NOW())
          $levelClause
          $verifiedClause
          $userClause
        ORDER BY score DESC
        LIMIT \$1
      ''', [count]);

      return Response.json({
        'ads': ads
            .whereType<Map<String, dynamic>>()
            .map((ad) => {
                  'id': ad['id'],
                  'title': ad['title'],
                  'body': ad['body'],
                  'image_url': ad['image_url'],
                  'thumbnail_url': ad['thumbnail_url'] ?? '',
                  'video_url': ad['video_url'] ?? '',
                  'media_kind': ad['media_kind'] ?? 'image',
                  'storage_bucket': ad['storage_bucket'] ?? '',
                  'storage_path': ad['storage_path'] ?? '',
                  'mime_type': ad['mime_type'] ?? '',
                  'target_url': ad['target_url'],
                  'item_type': 'ad',
                })
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      print('[Ads] getAds error: $e');
      return Response.json({'ads': []}, HttpStatus.ok);
    }
  }

  // ─── Impression tracking ─────────────────────────────────────────────────

  /// POST /api/ads/:id/impression  (authenticated)
  /// Records an impression and deducts CPM cost from ad budget.
  Future<Response> recordImpression(Request request, [dynamic _]) async {
    final adId = request.params()['id'] as String? ?? '';
    final userId = request.input('auth_user_id')?.toString() ?? '';
    if (adId.isEmpty || userId.isEmpty) {
      return Response.json({'message': 'Bad request'}, 400);
    }

    try {
      final now = DateTime.now().toIso8601String();

      // Idempotent — don't double-record for same user today
      final existing = await connection!.select(
        "SELECT id FROM ad_impressions WHERE ad_id = \$1 AND user_id = \$2 AND created_at::date = CURRENT_DATE LIMIT 1",
        [adId, userId],
      );
      if (existing.isNotEmpty) {
        return Response.json({'message': 'Already recorded'}, 200);
      }

      // Record impression
      await connection!.statement(
        'INSERT INTO ad_impressions (id, ad_id, user_id, created_at) VALUES (\$1, \$2, \$3, \$4)',
        [const Uuid().v4(), adId, userId, now],
      );

      // Deduct CPM cost and increment counter
      await connection!.statement('''
        UPDATE ads SET
          spent_bling = spent_bling + GREATEST(1, cpm_bling / 1000),
          total_impressions = total_impressions + 1,
          status = CASE
            WHEN spent_bling + GREATEST(1, cpm_bling / 1000) >= budget_bling THEN 'exhausted'
            ELSE status
          END
        WHERE id = \$1
      ''', [adId]);

      return Response.json({'message': 'ok'}, 200);
    } catch (e) {
      return Response.json({'message': 'Error'}, 500);
    }
  }

  // ─── Click tracking ──────────────────────────────────────────────────────

  /// POST /api/ads/:id/click  (authenticated)
  Future<Response> recordClick(Request request, [dynamic _]) async {
    final adId = request.params()['id'] as String? ?? '';
    final userId = request.input('auth_user_id')?.toString() ?? '';
    if (adId.isEmpty || userId.isEmpty) {
      return Response.json({'message': 'Bad request'}, 400);
    }

    try {
      final now = DateTime.now().toIso8601String();
      await connection!.statement(
        'INSERT INTO ad_clicks (id, ad_id, user_id, created_at) VALUES (\$1, \$2, \$3, \$4)',
        [const Uuid().v4(), adId, userId, now],
      );
      await connection!.statement(
        'UPDATE ads SET total_clicks = total_clicks + 1 WHERE id = \$1',
        [adId],
      );
      return Response.json({'message': 'ok'}, 200);
    } catch (e) {
      return Response.json({'message': 'Error'}, 500);
    }
  }

  // ─── Campaign creation ───────────────────────────────────────────────────

  /// POST /api/ads  (authenticated)
  /// Body: { title, body, image_url, target_url?, budget_bling, cpm_bling?,
  ///         target_min_level?, target_verified_only?, start_at?, end_at? }
  ///
  /// Deducts budget_bling from advertiser's wallet immediately.
  Future<Response> createAd(Request request) async {
    final advertiserId = request.input('auth_user_id')?.toString() ?? '';
    if (advertiserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final data = RequestData(request);
    final title = data.trimmed('title');
    final adBody = data.trimmed('body');
    final imageUrl = data.trimmed('image_url');
    final thumbnailUrl = data.trimmed('thumbnail_url');
    final videoUrl = data.trimmed('video_url');
    final mediaKind = data.trimmed('media_kind', fallback: 'image');
    final storageBucket = data.trimmed('storage_bucket');
    final storagePath = data.trimmed('storage_path');
    final mimeType = data.trimmed('mime_type');
    final targetUrl = data.trimmed('target_url');
    final budgetBling = data.intValue('budget_bling') ?? 0;
    final cpmBling = data.intValue('cpm_bling') ?? 50;
    final targetMinLevel = data.intValue('target_min_level');
    final targetVerifiedOnly = data.boolValue('target_verified_only');
    final startAt = data.trimmed('start_at').isEmpty ? null : data.trimmed('start_at');
    final endAt = data.trimmed('end_at').isEmpty ? null : data.trimmed('end_at');

    if (title.isEmpty || adBody.isEmpty) {
      return Response.json({'message': 'Title and body are required'}, 422);
    }
    if (budgetBling < 100) {
      return Response.json({'message': 'Minimum budget is 100 Bling'}, 422);
    }

    // Check wallet balance
    final wallet =
        await Wallet().query().where('user_id', '=', advertiserId).first();
    if (wallet == null || (wallet['balance'] as num).toInt() < budgetBling) {
      return Response.json({'message': 'Insufficient Bling balance'}, 400);
    }

    final now = DateTime.now().toIso8601String();
    final adId = const Uuid().v4();

    // Deduct budget from wallet
    final newBalance = (wallet['balance'] as num).toInt() - budgetBling;
    await Wallet().query().where('user_id', '=', advertiserId).update({
      'balance': newBalance,
      'updated_at': now,
    });

    // Create campaign
    await connection!.statement('''
      INSERT INTO ads (
        id, advertiser_id, title, body, image_url, target_url,
        thumbnail_url, video_url, media_kind, storage_bucket, storage_path, mime_type,
        budget_bling, spent_bling, cpm_bling,
        target_min_level, target_verified_only,
        start_at, end_at, status, is_active,
        total_impressions, total_clicks,
        created_at, updated_at
      ) VALUES (
        \$1, \$2, \$3, \$4, \$5, \$6,
        \$7, \$8, \$9, \$10, \$11, \$12,
        \$13, 0, \$14,
        \$15, \$16,
        \$17, \$18, 'active', 1,
        0, 0,
        \$19, \$19
      )
    ''', [
      adId,
      advertiserId,
      title,
      adBody,
      imageUrl,
      targetUrl,
      thumbnailUrl,
      videoUrl,
      mediaKind,
      storageBucket,
      storagePath,
      mimeType,
      budgetBling,
      cpmBling,
      targetMinLevel,
      targetVerifiedOnly,
      startAt,
      endAt,
      now,
    ]);

    // Estimate reach: budget / (cpm / 1000)
    final costPerImpression = cpmBling / 1000;
    final estimatedReach =
        costPerImpression > 0 ? (budgetBling / costPerImpression).round() : 0;

    return Response.json({
      'message': 'Campaign created successfully',
      'ad_id': adId,
      'budget_bling': budgetBling,
      'estimated_reach': estimatedReach,
      'new_wallet_balance': newBalance,
    }, HttpStatus.ok);
  }

  // ─── My campaigns ────────────────────────────────────────────────────────

  /// GET /api/ads/my  (authenticated)
  Future<Response> myCampaigns(Request request) async {
    final advertiserId = request.input('auth_user_id')?.toString() ?? '';
    if (advertiserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    try {
      final ads = await connection!.select('''
        SELECT id, title, body, image_url, thumbnail_url, video_url,
               media_kind, storage_bucket, storage_path, mime_type, target_url,
               budget_bling, spent_bling, cpm_bling,
               target_min_level, target_verified_only,
               total_impressions, total_clicks, status,
               start_at, end_at, created_at,
               CASE WHEN total_impressions > 0
                 THEN ROUND(total_clicks::numeric / total_impressions * 100, 2)
                 ELSE 0 END AS ctr_percent,
               budget_bling - spent_bling AS remaining_bling
        FROM ads
        WHERE advertiser_id = \$1
        ORDER BY created_at DESC
      ''', [advertiserId]);

      return Response.json({
        'campaigns': ads
            .map((a) => {
                  'id': a['id'],
                  'title': a['title'],
                  'body': a['body'],
                  'image_url': a['image_url'],
                  'thumbnail_url': a['thumbnail_url'] ?? '',
                  'video_url': a['video_url'] ?? '',
                  'media_kind': a['media_kind'] ?? 'image',
                  'storage_bucket': a['storage_bucket'] ?? '',
                  'storage_path': a['storage_path'] ?? '',
                  'mime_type': a['mime_type'] ?? '',
                  'target_url': a['target_url'],
                  'budget_bling': a['budget_bling'],
                  'spent_bling': a['spent_bling'],
                  'remaining_bling': a['remaining_bling'],
                  'cpm_bling': a['cpm_bling'],
                  'target_min_level': a['target_min_level'],
                  'target_verified_only': a['target_verified_only'],
                  'total_impressions': a['total_impressions'],
                  'total_clicks': a['total_clicks'],
                  'ctr_percent': a['ctr_percent'],
                  'status': a['status'],
                  'start_at': a['start_at']?.toString(),
                  'end_at': a['end_at']?.toString(),
                  'created_at': a['created_at']?.toString(),
                })
            .toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error: $e'}, 500);
    }
  }

  // ─── Pause / resume / delete ─────────────────────────────────────────────

  /// PUT /api/ads/:id  (authenticated)
  /// Body:
  ///  - { status: 'active' | 'paused' } for status-only updates
  ///  - full campaign payload for edit
  Future<Response> updateAd(Request request, [dynamic _]) async {
    final advertiserId = request.input('auth_user_id')?.toString() ?? '';
    final adId = request.params()['id'] as String? ?? '';
    if (advertiserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final data = RequestData(request);

    final rows = await connection!.select(
      '''
      SELECT id, advertiser_id, status, budget_bling, spent_bling
      FROM ads
      WHERE id = \$1
      LIMIT 1
      ''',
      [adId],
    );
    if (rows.isEmpty) return Response.json({'message': 'Not found'}, 404);
    if (rows.first['advertiser_id'] != advertiserId) {
      return Response.json({'message': 'Forbidden'}, 403);
    }

    final current = rows.first;
    final statusOnly = data.body.keys.length == 1 && data.body.containsKey('status');
    if (statusOnly) {
      final status = data.trimmed('status');
      if (!['active', 'paused'].contains(status)) {
        return Response.json(
            {'message': 'status must be active or paused'}, 422);
      }
      await connection!.statement(
        "UPDATE ads SET status = \$1, updated_at = \$2 WHERE id = \$3",
        [status, DateTime.now().toIso8601String(), adId],
      );
      return Response.json(
          {'message': 'Campaign updated', 'status': status}, 200);
    }

    final title = data.trimmed('title');
    final adBody = data.trimmed('body');
    final budgetBling = data.intValue('budget_bling') ?? 0;
    final cpmBling = data.intValue('cpm_bling') ?? 50;
    final targetMinLevel = data.intValue('target_min_level');
    final targetVerifiedOnly = data.boolValue('target_verified_only');
    final status = data.trimmed('status').isEmpty
        ? current['status']?.toString() ?? 'active'
        : data.trimmed('status');

    if (title.isEmpty || adBody.isEmpty) {
      return Response.json({'message': 'Title and body are required'}, 422);
    }
    if (budgetBling < 100) {
      return Response.json({'message': 'Minimum budget is 100 Bling'}, 422);
    }
    if (!['active', 'paused', 'exhausted'].contains(status)) {
      return Response.json({'message': 'Invalid status'}, 422);
    }

    final currentBudget = (current['budget_bling'] as num?)?.toInt() ?? 0;
    final spentBling = (current['spent_bling'] as num?)?.toInt() ?? 0;
    if (budgetBling < spentBling) {
      return Response.json(
          {'message': 'Budget cannot be less than already spent Bling'}, 422);
    }

    final wallet =
        await Wallet().query().where('user_id', '=', advertiserId).first();
    if (wallet == null) {
      return Response.json({'message': 'Wallet not found'}, 404);
    }

    final now = DateTime.now().toIso8601String();
    final budgetDelta = budgetBling - currentBudget;
    final currentBalance = (wallet['balance'] as num?)?.toInt() ?? 0;
    var newBalance = currentBalance;

    if (budgetDelta > 0) {
      if (currentBalance < budgetDelta) {
        return Response.json({'message': 'Insufficient Bling balance'}, 400);
      }
      newBalance = currentBalance - budgetDelta;
    } else if (budgetDelta < 0) {
      newBalance = currentBalance + (-budgetDelta);
    }

    if (budgetDelta != 0) {
      await Wallet().query().where('user_id', '=', advertiserId).update({
        'balance': newBalance,
        'updated_at': now,
      });
    }

    await connection!.statement(
      '''
      UPDATE ads
      SET title = \$1,
          body = \$2,
          image_url = \$3,
          target_url = \$4,
          thumbnail_url = \$5,
          video_url = \$6,
          media_kind = \$7,
          storage_bucket = \$8,
          storage_path = \$9,
          mime_type = \$10,
          budget_bling = \$11,
          cpm_bling = \$12,
          target_min_level = \$13,
          target_verified_only = \$14,
          start_at = \$15,
          end_at = \$16,
          status = \$17,
          updated_at = \$18
      WHERE id = \$19
      ''',
      [
        title,
        adBody,
        data.trimmed('image_url'),
        data.trimmed('target_url'),
        data.trimmed('thumbnail_url'),
        data.trimmed('video_url'),
        data.trimmed('media_kind', fallback: 'image'),
        data.trimmed('storage_bucket'),
        data.trimmed('storage_path'),
        data.trimmed('mime_type'),
        budgetBling,
        cpmBling,
        targetMinLevel,
        targetVerifiedOnly,
        data.trimmed('start_at').isEmpty ? null : data.trimmed('start_at'),
        data.trimmed('end_at').isEmpty ? null : data.trimmed('end_at'),
        budgetBling <= spentBling ? 'exhausted' : status,
        now,
        adId,
      ],
    );

    return Response.json({
      'message': 'Campaign updated',
      'new_wallet_balance': newBalance,
      'budget_bling': budgetBling,
      'spent_bling': spentBling,
    }, 200);
  }
}

final AdController adController = AdController();
