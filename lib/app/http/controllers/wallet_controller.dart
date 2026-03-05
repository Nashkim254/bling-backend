import 'dart:io';

import 'package:bling/app/models/bling_package.dart';
import 'package:bling/app/models/bling_transaction.dart';
import 'package:bling/app/models/notification_model.dart';
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
        'recent_transactions': (transactions as List).map((t) => {
              'id': t['id'],
              'type': t['type'],
              'amount': t['amount'],
              'to_user_id': t['to_user_id'],
              'description': t['description'],
              'created_at': t['created_at'].toString(),
            }).toList(),
      }
    }, HttpStatus.ok);
  }

  /// GET /api/wallet/transactions?page=&limit=  (authenticated)
  Future<Response> getTransactions(Request request) async {
    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final page =
        int.tryParse(request.input('page')?.toString() ?? '1') ?? 1;
    final limit =
        int.tryParse(request.input('limit')?.toString() ?? '20') ?? 20;

    final transactions = await BlingTransaction()
        .query()
        .where('user_id', '=', authUserId)
        .orderBy('created_at', 'DESC')
        .paginate(limit, page);

    return Response.json({'transactions': transactions}, HttpStatus.ok);
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
    request.validate({
      'package_id': 'required|string',
    }, {
      'package_id.required': 'Package ID is required',
    });

    final authUserId = request.input('auth_user_id') as String? ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final body = request.body;
    final packageId = body['package_id'] as String;
    final paymentRef = body['payment_reference'] as String? ?? '';

    final package =
        await BlingPackage().query().where('id', '=', packageId).first();
    if (package == null) {
      return Response.json({'message': 'Package not found'}, 404);
    }
    if (package['is_active'] == 0) {
      return Response.json({'message': 'Package is no longer available'}, 400);
    }

    final blingAmount = package['bling_amount'] as int;
    final now = DateTime.now().toIso8601String();

    // Add bling to wallet
    var wallet =
        await Wallet().query().where('user_id', '=', authUserId).first();
    if (wallet == null) {
      final walletId = const Uuid().v4();
      await Wallet().query().insert({
        'id': walletId,
        'user_id': authUserId,
        'balance': blingAmount,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      final newBalance = (wallet['balance'] as int) + blingAmount;
      await Wallet().query().where('user_id', '=', authUserId).update({
        'balance': newBalance,
        'updated_at': now,
      });
    }

    // Record transaction
    await BlingTransaction().query().insert({
      'id': const Uuid().v4(),
      'user_id': authUserId,
      'type': 'purchase',
      'amount': blingAmount,
      'reference': paymentRef,
      'description': 'Purchased ${package['name']} package',
      'created_at': now,
      'updated_at': now,
    });

    // Update bling_score
    final user = await User().query().where('id', '=', authUserId).first();
    final newScore = ((user?['bling_score'] as int?) ?? 0) + blingAmount;
    await User().query().where('id', '=', authUserId).update({
      'bling_score': newScore,
      'updated_at': now,
    });

    final updatedWallet =
        await Wallet().query().where('user_id', '=', authUserId).first();

    return Response.json({
      'message': 'Bling purchased successfully',
      'bling_added': blingAmount,
      'new_balance': updatedWallet?['balance'] ?? blingAmount,
    }, HttpStatus.ok);
  }

  /// POST /api/bling/transfer  (authenticated)
  /// Body: { to_user_id, amount, message?, context? }
  /// context: 'direct' (default) | 'post_tip' | 'challenge_tip'
  ///
  /// Commission (PLATFORM_COMMISSION_RATE %) is applied when context != 'direct'.
  /// Sender pays the full amount; recipient receives amount minus fee.
  Future<Response> transferBling(Request request) async {
    request.validate({
      'to_user_id': 'required|string',
      'amount': 'required',
    }, {
      'to_user_id.required': 'Recipient is required',
      'amount.required': 'Amount is required',
    });

    final authUserId = request.input('auth_user_id')?.toString() ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final body = request.body;
    final toUserId = body['to_user_id'] as String;
    final amount = int.tryParse(body['amount']?.toString() ?? '0') ?? 0;
    final message = body['message'] as String? ?? '';
    final context = body['context'] as String? ?? 'direct';

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

    // ── Commission ────────────────────────────────────────────────────────
    final isTip = context == 'post_tip' || context == 'challenge_tip';
    final commissionRate =
        int.tryParse(Platform.environment['PLATFORM_COMMISSION_RATE'] ?? '5') ?? 5;
    final feeAmount = isTip ? (amount * commissionRate / 100).floor() : 0;
    final recipientAmount = amount - feeAmount;

    // ── Check sender balance ──────────────────────────────────────────────
    final senderWallet =
        await Wallet().query().where('user_id', '=', authUserId).first();
    if (senderWallet == null ||
        (senderWallet['balance'] as num).toInt() < amount) {
      return Response.json({'message': 'Insufficient bling balance'}, 400);
    }

    final now = DateTime.now().toIso8601String();
    final sender = await User().query().where('id', '=', authUserId).first();

    // ── Deduct full amount from sender ────────────────────────────────────
    final newSenderBalance =
        (senderWallet['balance'] as num).toInt() - amount;
    await Wallet().query().where('user_id', '=', authUserId).update({
      'balance': newSenderBalance,
      'updated_at': now,
    });

    // ── Credit recipient (amount minus fee) ───────────────────────────────
    var recipientWallet =
        await Wallet().query().where('user_id', '=', toUserId).first();
    if (recipientWallet == null) {
      await Wallet().query().insert({
        'id': const Uuid().v4(),
        'user_id': toUserId,
        'balance': recipientAmount,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      final newRecipientBalance =
          (recipientWallet['balance'] as num).toInt() + recipientAmount;
      await Wallet().query().where('user_id', '=', toUserId).update({
        'balance': newRecipientBalance,
        'updated_at': now,
      });
    }

    // ── Sender transaction (full debit) ───────────────────────────────────
    await BlingTransaction().query().insert({
      'id': const Uuid().v4(),
      'user_id': authUserId,
      'to_user_id': toUserId,
      'type': 'transfer_out',
      'amount': amount,
      'fee_amount': feeAmount,
      'context': context,
      'description': message.isNotEmpty
          ? 'Tipped ${recipient['name']}: $message'
          : isTip
              ? 'Tipped ${recipient['name']}'
              : 'Sent to ${recipient['name']}',
      'created_at': now,
      'updated_at': now,
    });

    // ── Recipient transaction (amount received after fee) ─────────────────
    await BlingTransaction().query().insert({
      'id': const Uuid().v4(),
      'user_id': toUserId,
      'to_user_id': authUserId,
      'type': 'transfer_in',
      'amount': recipientAmount,
      'fee_amount': feeAmount,
      'context': context,
      'description': message.isNotEmpty
          ? 'Tip from ${sender?['name']}: $message'
          : isTip
              ? 'Tip from ${sender?['name']}'
              : 'Received from ${sender?['name']}',
      'created_at': now,
      'updated_at': now,
    });

    // ── Platform commission transaction (fee audit trail) ─────────────────
    if (feeAmount > 0) {
      await BlingTransaction().query().insert({
        'id': const Uuid().v4(),
        'user_id': authUserId,   // who generated this fee
        'to_user_id': toUserId,  // whose tip it came from
        'type': 'platform_commission',
        'amount': feeAmount,
        'fee_amount': feeAmount,
        'context': context,
        'description': '${commissionRate}% tip commission on ${amount} Bling',
        'created_at': now,
        'updated_at': now,
      });
    }

    // ── Notify recipient ──────────────────────────────────────────────────
    final notifBody = isTip
        ? message.isNotEmpty
            ? '${sender?['name']} tipped you $recipientAmount Bling ($feeAmount fee): $message'
            : '${sender?['name']} tipped you $recipientAmount Bling'
        : message.isNotEmpty
            ? '${sender?['name']} sent you $amount Bling: $message'
            : '${sender?['name']} sent you $amount Bling';

    await NotificationModel().query().insert({
      'id': const Uuid().v4(),
      'user_id': toUserId,
      'type': isTip ? 'tip_received' : 'bling_received',
      'title': isTip ? 'You got a tip!' : 'Bling Received!',
      'body': notifBody,
      'data':
          '{"amount":$recipientAmount,"fee":$feeAmount,"from_user_id":"$authUserId"}',
      'is_read': 0,
      'created_at': now,
      'updated_at': now,
    });

    return Response.json({
      'message': isTip
          ? 'Tip sent! ${recipient['name']} received $recipientAmount Bling.'
          : 'Bling transferred successfully',
      'amount_sent': amount,
      'recipient_received': recipientAmount,
      'fee': feeAmount,
      'commission_rate': isTip ? commissionRate : 0,
      'new_balance': newSenderBalance,
      'recipient': recipient['name'],
    }, HttpStatus.ok);
  }
}

final WalletController walletController = WalletController();
