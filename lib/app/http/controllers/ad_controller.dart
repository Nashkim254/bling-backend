import 'dart:io';

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
    final userLevel = int.tryParse(request.input('user_level')?.toString() ?? '1') ?? 1;
    final isVerified = request.input('is_verified')?.toString() == 'true';

    try {
      final userClause = userId.isNotEmpty
          ? "AND NOT EXISTS (SELECT 1 FROM ad_impressions ai WHERE ai.ad_id = a.id AND ai.user_id = '$userId' AND ai.created_at::date = CURRENT_DATE)"
          : '';

      final verifiedClause =
          isVerified ? '' : 'AND (a.target_verified_only = false OR a.target_verified_only IS NULL)';

      final levelClause =
          'AND (a.target_min_level IS NULL OR a.target_min_level <= $userLevel)';

      final ads = await connection!.select('''
        SELECT
          a.id, a.title, a.body, a.image_url, a.target_url,
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
        'ads': (ads).map((ad) => {
              'id': ad['id'],
              'title': ad['title'],
              'body': ad['body'],
              'image_url': ad['image_url'],
              'target_url': ad['target_url'],
              'item_type': 'ad',
            }).toList(),
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

    final body = request.body;
    final title = body['title']?.toString() ?? '';
    final adBody = body['body']?.toString() ?? '';
    final imageUrl = body['image_url']?.toString() ?? '';
    final targetUrl = body['target_url']?.toString() ?? '';
    final budgetBling = int.tryParse(body['budget_bling']?.toString() ?? '0') ?? 0;
    final cpmBling = int.tryParse(body['cpm_bling']?.toString() ?? '50') ?? 50;
    final targetMinLevel = int.tryParse(body['target_min_level']?.toString() ?? '');
    final targetVerifiedOnly = body['target_verified_only'] == true || body['target_verified_only'] == 'true';
    final startAt = body['start_at']?.toString();
    final endAt = body['end_at']?.toString();

    if (title.isEmpty || adBody.isEmpty) {
      return Response.json({'message': 'Title and body are required'}, 422);
    }
    if (budgetBling < 100) {
      return Response.json({'message': 'Minimum budget is 100 Bling'}, 422);
    }

    // Check wallet balance
    final wallet = await Wallet().query().where('user_id', '=', advertiserId).first();
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
        budget_bling, spent_bling, cpm_bling,
        target_min_level, target_verified_only,
        start_at, end_at, status, is_active,
        total_impressions, total_clicks,
        created_at, updated_at
      ) VALUES (
        \$1, \$2, \$3, \$4, \$5, \$6,
        \$7, 0, \$8,
        \$9, \$10,
        \$11, \$12, 'active', 1,
        0, 0,
        \$13, \$13
      )
    ''', [
      adId, advertiserId, title, adBody, imageUrl, targetUrl,
      budgetBling, cpmBling,
      targetMinLevel, targetVerifiedOnly,
      startAt, endAt, now,
    ]);

    // Estimate reach: budget / (cpm / 1000)
    final costPerImpression = cpmBling / 1000;
    final estimatedReach = costPerImpression > 0
        ? (budgetBling / costPerImpression).round()
        : 0;

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
        SELECT id, title, body, image_url, target_url,
               budget_bling, spent_bling, cpm_bling,
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
        'campaigns': ads.map((a) => {
              'id': a['id'],
              'title': a['title'],
              'body': a['body'],
              'image_url': a['image_url'],
              'target_url': a['target_url'],
              'budget_bling': a['budget_bling'],
              'spent_bling': a['spent_bling'],
              'remaining_bling': a['remaining_bling'],
              'cpm_bling': a['cpm_bling'],
              'total_impressions': a['total_impressions'],
              'total_clicks': a['total_clicks'],
              'ctr_percent': a['ctr_percent'],
              'status': a['status'],
              'start_at': a['start_at']?.toString(),
              'end_at': a['end_at']?.toString(),
              'created_at': a['created_at']?.toString(),
            }).toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'message': 'Error: $e'}, 500);
    }
  }

  // ─── Pause / resume / delete ─────────────────────────────────────────────

  /// PUT /api/ads/:id  (authenticated)
  /// Body: { status: 'active' | 'paused' }
  Future<Response> updateAd(Request request, [dynamic _]) async {
    final advertiserId = request.input('auth_user_id')?.toString() ?? '';
    final adId = request.params()['id'] as String? ?? '';
    if (advertiserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final status = request.body['status']?.toString() ?? '';
    if (!['active', 'paused'].contains(status)) {
      return Response.json({'message': 'status must be active or paused'}, 422);
    }

    final rows = await connection!.select(
      'SELECT id, advertiser_id FROM ads WHERE id = \$1 LIMIT 1',
      [adId],
    );
    if (rows.isEmpty) return Response.json({'message': 'Not found'}, 404);
    if (rows.first['advertiser_id'] != advertiserId) {
      return Response.json({'message': 'Forbidden'}, 403);
    }

    await connection!.statement(
      "UPDATE ads SET status = \$1, updated_at = \$2 WHERE id = \$3",
      [status, DateTime.now().toIso8601String(), adId],
    );

    return Response.json({'message': 'Campaign updated', 'status': status}, 200);
  }
}

final AdController adController = AdController();
