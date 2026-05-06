import 'dart:convert';
import 'dart:io';

import 'package:bling/app/http/request_data.dart';
import 'package:bling/app/models/bling_package.dart';
import 'package:bling/app/models/bling_transaction.dart';
import 'package:bling/app/models/notification_model.dart';
import 'package:bling/app/models/user.dart';
import 'package:bling/app/models/wallet.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class PurchaseController extends Controller {
  /// POST /api/bling/purchase/verify  (authenticated)
  ///
  /// Body (iOS):
  ///   { platform: 'ios', package_id, receipt_data: '<base64>' }
  ///
  /// Body (Android):
  ///   { platform: 'android', package_id, purchase_token, product_id }
  Future<Response> verifyPurchase(Request request) async {
    final authUserId = request.input('auth_user_id')?.toString() ?? '';
    if (authUserId.isEmpty) {
      return Response.json({'message': 'Unauthenticated'}, 401);
    }

    final data = RequestData(request);
    final body = data.body;
    final platform = data.lower('platform');
    final packageId = data.trimmed('package_id');

    if (packageId.isEmpty) {
      return Response.json({'message': 'package_id is required'}, 422);
    }

    final package =
        await BlingPackage().query().where('id', '=', packageId).first();
    if (package == null || package['is_active'] == 0) {
      return Response.json({'message': 'Package not found or inactive'}, 404);
    }

    final blingAmount = (package['bling_amount'] as num).toInt();
    String? storeTransactionId;

    // ─── Platform verification ────────────────────────────────────────────
    if (platform == 'ios') {
      final result = await _verifyIos(body, package);
      if (result['error'] != null) {
        return Response.json({'message': result['error']}, 400);
      }
      storeTransactionId = result['transaction_id'] as String?;
    } else if (platform == 'android') {
      final result = await _verifyAndroid(body, package);
      if (result['error'] != null) {
        return Response.json({'message': result['error']}, 400);
      }
      storeTransactionId = result['transaction_id'] as String?;
    } else {
      return Response.json({'message': 'Invalid platform'}, 422);
    }

    // ─── Idempotency — check if already processed ─────────────────────────
    if (storeTransactionId != null && storeTransactionId.isNotEmpty) {
      final existing = await connection!.select(
        'SELECT id FROM bling_transactions WHERE store_transaction_id = \$1 LIMIT 1',
        [storeTransactionId],
      );
      if (existing.isNotEmpty) {
        // Already credited — return current balance without re-crediting
        final w =
            await Wallet().query().where('user_id', '=', authUserId).first();
        return Response.json({
          'message': 'Already processed',
          'new_balance': (w?['balance'] as num?)?.toInt() ?? 0,
        }, HttpStatus.ok);
      }
    }

    // ─── Credit wallet ────────────────────────────────────────────────────
    final now = DateTime.now().toIso8601String();
    var wallet =
        await Wallet().query().where('user_id', '=', authUserId).first();
    int newBalance;
    if (wallet == null) {
      newBalance = blingAmount;
      await Wallet().query().insert({
        'id': const Uuid().v4(),
        'user_id': authUserId,
        'balance': blingAmount,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      newBalance = (wallet['balance'] as num).toInt() + blingAmount;
      await Wallet().query().where('user_id', '=', authUserId).update({
        'balance': newBalance,
        'updated_at': now,
      });
    }

    // ─── Record transaction ───────────────────────────────────────────────
    await BlingTransaction().query().insert({
      'id': const Uuid().v4(),
      'user_id': authUserId,
      'type': 'purchase',
      'amount': blingAmount,
      'platform': platform,
      'store_transaction_id': storeTransactionId,
      'reference': storeTransactionId,
      'description': 'Purchased ${package['name']} package via $platform',
      'created_at': now,
      'updated_at': now,
    });

    // ─── Bump bling_score ─────────────────────────────────────────────────
    final user = await User().query().where('id', '=', authUserId).first();
    final newScore =
        ((user?['bling_score'] as num?)?.toInt() ?? 0) + blingAmount;
    await User().query().where('id', '=', authUserId).update({
      'bling_score': newScore,
      'updated_at': now,
    });

    // ─── Notify user ──────────────────────────────────────────────────────
    await NotificationModel().query().insert({
      'id': const Uuid().v4(),
      'user_id': authUserId,
      'type': 'bling_purchased',
      'title': 'Bling Purchased!',
      'body': '$blingAmount Bling added to your wallet.',
      'data': '{"amount":$blingAmount}',
      'is_read': 0,
      'created_at': now,
      'updated_at': now,
    });

    return Response.json({
      'message': '$blingAmount Bling added to your wallet!',
      'bling_added': blingAmount,
      'new_balance': newBalance,
    }, HttpStatus.ok);
  }

  // ─── iOS Receipt Verification ───────────────────────────────────────────
  Future<Map<String, dynamic>> _verifyIos(
    Map<String, dynamic> body,
    Map<String, dynamic> package,
  ) async {
    final receiptData = body['receipt_data'] as String? ?? '';
    if (receiptData.isEmpty) {
      return {'error': 'receipt_data is required for iOS'};
    }

    final sharedSecret = Platform.environment['APPLE_SHARED_SECRET'] ?? '';
    final iapEnv = Platform.environment['APPLE_IAP_ENV'] ?? 'sandbox';
    final sandboxUrl = 'https://sandbox.itunes.apple.com/verifyReceipt';
    final productionUrl = 'https://buy.itunes.apple.com/verifyReceipt';

    final payload = {
      'receipt-data': receiptData,
      'password': sharedSecret,
      'exclude-old-transactions': true,
    };

    // Try production first; if status=21007 retry with sandbox
    final urls = iapEnv == 'production'
        ? [productionUrl, sandboxUrl]
        : [sandboxUrl, productionUrl];

    Map<String, dynamic>? appleResp;
    for (final url in urls) {
      try {
        final resp = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 15));

        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = decoded['status'] as int? ?? -1;

        // status 21007 = sandbox receipt sent to production → switch URL
        if (status == 21007 && url == productionUrl) continue;

        appleResp = decoded;
        break;
      } catch (_) {
        continue;
      }
    }

    if (appleResp == null) {
      return {'error': 'Could not reach Apple verification server'};
    }

    final status = appleResp['status'] as int? ?? -1;
    if (status != 0) {
      return {'error': 'Apple receipt invalid (status=$status)'};
    }

    // Find matching in-app purchase in receipt
    final receipt = appleResp['receipt'] as Map<String, dynamic>?;
    final inApp = receipt?['in_app'] as List? ?? [];
    final storeProductId = package['store_product_id'] as String? ?? '';

    final matching = inApp.cast<Map<String, dynamic>>().where(
          (t) => t['product_id'] == storeProductId,
        );

    if (matching.isEmpty) {
      return {'error': 'No matching product in receipt'};
    }

    // Use the most recent transaction
    final transaction = matching.reduce((a, b) {
      final aTime = int.tryParse(a['purchase_date_ms']?.toString() ?? '0') ?? 0;
      final bTime = int.tryParse(b['purchase_date_ms']?.toString() ?? '0') ?? 0;
      return aTime > bTime ? a : b;
    });

    return {'transaction_id': transaction['transaction_id']?.toString()};
  }

  // ─── Android Purchase Token Verification ────────────────────────────────
  Future<Map<String, dynamic>> _verifyAndroid(
    Map<String, dynamic> body,
    Map<String, dynamic> package,
  ) async {
    final purchaseToken = body['purchase_token'] as String? ?? '';
    final productId = body['product_id'] as String? ?? '';

    if (purchaseToken.isEmpty || productId.isEmpty) {
      return {
        'error': 'purchase_token and product_id are required for Android'
      };
    }

    // Verify product matches package
    final storeProductId = package['store_product_id'] as String? ?? '';
    if (productId != storeProductId) {
      return {'error': 'Product ID mismatch'};
    }

    final serviceAccountJson =
        Platform.environment['GOOGLE_SERVICE_ACCOUNT_JSON'] ?? '';
    final packageName = Platform.environment['GOOGLE_PLAY_PACKAGE_NAME'] ?? '';

    if (serviceAccountJson.isEmpty) {
      return {
        'error': 'Google Play verification is not configured on the server'
      };
    }

    if (packageName.isEmpty) {
      return {
        'error': 'Google Play package name is not configured on the server'
      };
    }

    // ── Get OAuth2 access token from service account ──────────────────────
    try {
      final accessToken = await _getGoogleAccessToken(serviceAccountJson);
      if (accessToken == null) {
        return {'error': 'Could not authenticate with Google Play'};
      }

      // ── Call Play Developer API ───────────────────────────────────────
      final uri = Uri.parse(
        'https://androidpublisher.googleapis.com/androidpublisher/v3'
        '/applications/$packageName/purchases/products/$productId/tokens/$purchaseToken',
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return {
          'error': 'Google Play verification failed (${resp.statusCode})'
        };
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // purchaseState: 0 = purchased, 1 = cancelled, 2 = pending
      final purchaseState = data['purchaseState'] as int? ?? -1;
      if (purchaseState != 0) {
        return {'error': 'Purchase not in purchased state ($purchaseState)'};
      }

      final consumptionState = data['consumptionState'] as int? ?? -1;
      if (consumptionState == 1) {
        return {'error': 'Purchase token has already been consumed'};
      }

      final orderId = data['orderId'] as String? ?? purchaseToken;
      return {'transaction_id': orderId};
    } catch (e) {
      return {'error': 'Android verification error: $e'};
    }
  }

  /// Creates a signed JWT and exchanges it for a Google OAuth2 access token.
  /// Uses openssl subprocess with temp files for RSA-SHA256 signing.
  Future<String?> _getGoogleAccessToken(String serviceAccountJson) async {
    final tempDir = Directory.systemTemp;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final keyFile = File('${tempDir.path}/gsa_key_$ts.pem');
    final dataFile = File('${tempDir.path}/gsa_data_$ts.txt');
    final sigFile = File('${tempDir.path}/gsa_sig_$ts.bin');

    try {
      final sa = jsonDecode(serviceAccountJson) as Map<String, dynamic>;
      final clientEmail = sa['client_email'] as String;
      final privateKeyPem = sa['private_key'] as String;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Build JWT header + claims (unpadded base64url)
      String b64(String json) =>
          base64Url.encode(utf8.encode(json)).replaceAll('=', '');

      final header = b64(jsonEncode({'alg': 'RS256', 'typ': 'JWT'}));
      final claims = b64(jsonEncode({
        'iss': clientEmail,
        'scope': 'https://www.googleapis.com/auth/androidpublisher',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
      }));

      final signingInput = '$header.$claims';

      // Write key and signing input to temp files
      await keyFile.writeAsString(privateKeyPem);
      await dataFile.writeAsString(signingInput);

      // Sign with openssl (available on macOS and most Linux servers)
      final result = await Process.run('openssl', [
        'dgst',
        '-sha256',
        '-sign',
        keyFile.path,
        '-out',
        sigFile.path,
        dataFile.path,
      ]);

      if (result.exitCode != 0) {
        print('[IAP] openssl signing failed: ${result.stderr}');
        return null;
      }

      final sigBytes = await sigFile.readAsBytes();
      final sig = base64Url.encode(sigBytes).replaceAll('=', '');
      final jwt = '$signingInput.$sig';

      // Exchange JWT for access token
      final tokenResp = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': jwt,
        },
      );

      final tokenData = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      return tokenData['access_token'] as String?;
    } catch (e) {
      print('[IAP] _getGoogleAccessToken error: $e');
      return null;
    } finally {
      // Always clean up temp files
      for (final f in [keyFile, dataFile, sigFile]) {
        f.delete().catchError((dynamic _) => f);
      }
    }
  }
}

final PurchaseController purchaseController = PurchaseController();
