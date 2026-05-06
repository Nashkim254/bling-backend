import 'dart:async';
import 'dart:io';

import 'package:bling/app/http/request_data.dart';
import 'package:bling/app/models/bling_package.dart';
import 'package:bling/app/models/bling_transaction.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/services/fcm_service.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class WalletController extends Controller {
  /// GET /api/wallet  (authenticated)
  Future<Response> getWallet(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    var wallet =
        await Wallet().query().where('user_id', '=', authUserId).first();

    // Create wallet if not exists
    if (wallet == null) {
      final now = DateTime.now().toIso8601String();
      final walletId = const Uuid().v4();
      await Wallet().query().insert({
        'id': walletId,
        'user_id': authUserId,
        'balance': 0,
        'created_at': now,
        'updated_at': now,
      });
      wallet = {'id': walletId, 'user_id': authUserId, 'balance': 0};
    }

    // Get recent transactions
    final transactions = await BlingTransaction()
        .query()
        .where('user_id', '=', authUserId)
        .orderBy('created_at', 'DESC')
        .limit(10)
        .get();

    return Response.json({
      'wallet': {
        'balance': wallet['balance'],
        'user_id': wallet['user_id'],
        'recent_transactions': (transactions as List)
            .map((t) => {
                  'id': t['id'],
                  'type': t['type'],
                  'amount': t['amount'],
                  'to_user_id': t['to_user_id'],
                  'description': t['description'],
                  'created_at': t['created_at'].toString(),
                })
            .toList(),
      }
    }, HttpStatus.ok);
  }

  /// GET /api/wallet/transactions?page=&limit=  (authenticated)
  Future<Response> getTransactions(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final page = int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit < 1 ? 20 : (limit > 100 ? 100 : limit);
    final offset = (safePage - 1) * safeLimit;

    try {
      final total = await BlingTransaction()
          .query()
          .where('user_id', '=', authUserId)
          .count();

      final rows = await BlingTransaction()
          .query()
          .where('user_id', '=', authUserId)
          .orderBy('created_at', 'DESC')
          .limit(safeLimit)
          .offset(offset)
          .get();

      final data = (rows as List)
          .whereType<Map>()
          .map((t) => {
                'id': t['id'],
                'type': t['type'],
                'amount': t['amount'],
                'to_user_id': t['to_user_id'],
                'description': t['description'],
                'reference': t['reference'],
                'created_at': t['created_at']?.toString(),
              })
          .toList();

      return Response.json({
        'transactions': {
          'data': data,
          'total': total,
          'page': safePage,
          'limit': safeLimit,
          'last_page': safeLimit == 0 ? 1 : ((total / safeLimit).ceil()),
        }
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({
        'message': 'Could not load wallet transactions',
        'error': e.toString(),
      }, 400);
    }
  }

  /// GET /api/bling/packages
  Future<Response> getPackages(Request request) async {
    final packages = await BlingPackage()
        .query()
        .where('is_active', '=', 1)
        .orderBy('bling_amount', 'ASC')
        .get();

    return Response.json({'packages': packages}, HttpStatus.ok);
  }

  /// POST /api/bling/purchase  (authenticated)
  /// Body: { package_id, payment_reference }
  Future<Response> purchaseBling(Request request) async {
    return Response.json({
      'message':
          'Direct wallet credit purchases are disabled. Use store-verified purchases via /api/bling/purchase/verify.',
    }, HttpStatus.gone);
  }

  /// POST /api/bling/transfer  (authenticated)
  /// Body: { to_user_id, amount, message?, context? }
  /// context: 'direct' (default) | 'post_tip' | 'challenge_tip'
  ///
  /// Phase 1 rules:
  /// - direct peer-to-peer transfers are disabled
  /// - creator support is consumed as platform spend
  /// - creators receive visibility credit, not wallet balance
  Future<Response> transferBling(Request request) async {
    final authUserId = request.input('auth_user_id')?.toString() ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final data = RequestData(request);
    final errors = data.require({
      'to_user_id': 'Recipient is required',
      'amount': 'Amount is required',
    });
    if (errors.isNotEmpty) {
      return Response.json(errors, 422);
    }

    final toUserId = data.trimmed('to_user_id');
    final amount = data.intValue('amount') ?? 0;
    final message = data.trimmed('message');
    final context = _normalizeTransferContext(data.trimmed('context', fallback: 'direct'));

    if (toUserId == authUserId) {
      return Response.json({'message': 'Cannot transfer to yourself'}, 400);
    }
    if (amount <= 0) {
      return Response.json({'message': 'Amount must be greater than 0'}, 400);
    }

    final recipient = await User().query().where('id', '=', toUserId).first();
    if (recipient == null) {
      return Response.json({'message': 'Recipient not found'}, 404);
    }

    if (context == 'direct') {
      return Response.json({
        'message': 'Direct Bling transfers are disabled in phase 1',
      }, 403);
    }

    // ── Commission ────────────────────────────────────────────────────────
    final isTip = _isCreatorSupportContext(context);
    final commissionRate =
        int.tryParse(Platform.environment['PLATFORM_COMMISSION_RATE'] ?? '5') ??
            5;
    final feeAmount = isTip ? (amount * commissionRate / 100).floor() : 0;
    final creatorCredit = amount - feeAmount;

    // ── Check sender balance ──────────────────────────────────────────────
    final senderWallet =
        await Wallet().query().where('user_id', '=', authUserId).first();
    if (senderWallet == null ||
        (senderWallet['balance'] as num).toInt() < amount) {
      return Response.json({'message': 'Insufficient bling balance'}, 400);
    }

    final now = DateTime.now().toIso8601String();
    final sender = await User().query().where('id', '=', authUserId).first();
    final transferReference = 'TR${DateTime.now().millisecondsSinceEpoch}';

    // ── Deduct full amount from sender ────────────────────────────────────
    final newSenderBalance = (senderWallet['balance'] as num).toInt() - amount;
    await Wallet().query().where('user_id', '=', authUserId).update({
      'balance': newSenderBalance,
      'updated_at': now,
    });

    // ── Sender transaction (full spend) ───────────────────────────────────
    await BlingTransaction().query().insert({
      'id': const Uuid().v4(),
      'user_id': authUserId,
      'to_user_id': toUserId,
      'type': 'support_spend',
      'amount': amount,
      'reference': transferReference,
      'fee_amount': feeAmount,
      'context': context,
      'description': message.isNotEmpty
          ? 'Supported ${recipient['name']}: $message'
          : 'Supported ${recipient['name']}',
      'created_at': now,
      'updated_at': now,
    });

    // ── Platform commission transaction (fee audit trail) ─────────────────
    if (feeAmount > 0) {
      await BlingTransaction().query().insert({
        'id': const Uuid().v4(),
        'user_id': authUserId, // who generated this fee
        'to_user_id': toUserId, // whose tip it came from
        'type': 'platform_commission',
        'amount': feeAmount,
        'reference': transferReference,
        'fee_amount': feeAmount,
        'context': context,
        'description': '$commissionRate% tip commission on $amount Bling',
        'created_at': now,
        'updated_at': now,
      });
    }

    // ── Creator visibility / support credit ───────────────────────────────
    final currentRecipientScore =
        (recipient['bling_score'] as num?)?.toInt() ?? 0;
    await User().query().where('id', '=', toUserId).update({
      'bling_score': currentRecipientScore + creatorCredit,
      'updated_at': now,
    });

    // ── Notify recipient ──────────────────────────────────────────────────
    final notifBody = message.isNotEmpty
        ? '${sender?['name']} supported you with $creatorCredit Bling credit: $message'
        : '${sender?['name']} supported you with $creatorCredit Bling credit';

    await NotificationModel().query().insert({
      'id': const Uuid().v4(),
      'user_id': toUserId,
      'type': 'creator_supported',
      'title': 'You got support!',
      'body': notifBody,
      'data':
          '{"amount":$creatorCredit,"fee":$feeAmount,"from_user_id":"$authUserId","context":"$context"}',
      'is_read': 0,
      'created_at': now,
      'updated_at': now,
    });

    // Push to recipient
    unawaited(FcmService.instance.sendToUser(
      toUserId,
      title: 'You got support! 💰',
      body: notifBody,
      data: {
        'type': 'creator_supported',
        'amount': creatorCredit.toString(),
        'from_user_id': authUserId
      },
    ));

    // Push to sender (confirmation)
    unawaited(FcmService.instance.sendToUser(
      authUserId,
      title: 'Support Sent!',
      body: 'You supported ${recipient['name']} with $amount Bling',
      data: {
        'type': 'support_sent',
        'amount': amount.toString(),
        'to_user_id': toUserId
      },
    ));

    return Response.json({
      'message': 'Support sent successfully',
      'reference': transferReference,
      'amount_spent': amount,
      'creator_credit': creatorCredit,
      'fee': feeAmount,
      'commission_rate': commissionRate,
      'new_balance': newSenderBalance,
      'recipient': recipient['name'],
      'created_at': now,
    }, HttpStatus.ok);
  }

  bool _isCreatorSupportContext(String context) =>
      context == 'post_tip' || context == 'challenge_tip';

  String _normalizeTransferContext(String context) {
    switch (context.trim()) {
      case 'post_support':
        return 'post_tip';
      case 'challenge_support':
        return 'challenge_tip';
      case 'post_tip':
      case 'challenge_tip':
        return context.trim();
      default:
        return 'direct';
    }
  }
}

final WalletController walletController = WalletController();
