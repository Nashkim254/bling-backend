import 'dart:io';
import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:vania/vania.dart';

class OtpController extends Controller {
  /// POST /api/otp/send
  /// Body: { email }
  Future<Response> sendOtp(Request request) async {
    final email = (request.input('email')?.toString() ?? '').trim().toLowerCase();
    if (email.isEmpty) {
      return Response.json({'message': 'Email is required'}, 422);
    }

    // type: 'forgot_password' (default) requires existing user
    //       'registration' requires email NOT already registered
    final type = (request.input('type')?.toString() ?? 'forgot_password').trim();

    final users = await connection!.select(
      'SELECT id FROM users WHERE email = \$1 AND deleted_at IS NULL LIMIT 1',
      [email],
    );

    if (type == 'registration') {
      if (users.isNotEmpty) {
        return Response.json({'message': 'Email already registered'}, 409);
      }
    } else {
      if (users.isEmpty) {
        return Response.json({'message': 'No account found with that email'}, 404);
      }
    }

    final code = _generateCode();
    final id = const Uuid().v4();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 10));

    // Remove any existing OTP for this email
    await connection!.statement(
      'DELETE FROM otps WHERE email = \$1',
      [email],
    );

    // Insert new OTP
    await connection!.statement(
      'INSERT INTO otps (id, email, code, expires_at, created_at) VALUES (\$1, \$2, \$3, \$4, \$5)',
      [id, email, code, expiresAt.toIso8601String(), now.toIso8601String()],
    );

    // TODO: Send via SMTP when email service is configured
    print('[OTP] ========================================');
    print('[OTP] Code for $email: $code');
    print('[OTP] Expires at: $expiresAt');
    print('[OTP] ========================================');

    return Response.json({
      'message': 'OTP sent to $email',
      // Remove in production — dev only
      'dev_code': code,
    }, HttpStatus.ok);
  }

  /// POST /api/otp/verify
  /// Body: { email, code }
  Future<Response> verifyOtp(Request request) async {
    final email = (request.input('email')?.toString() ?? '').trim().toLowerCase();
    final code = (request.input('code')?.toString() ?? '').trim().toUpperCase();

    if (email.isEmpty || code.isEmpty) {
      return Response.json({'message': 'Email and code are required'}, 422);
    }

    final rows = await connection!.select(
      'SELECT id, code, expires_at FROM otps WHERE email = \$1 ORDER BY created_at DESC LIMIT 1',
      [email],
    );

    if (rows.isEmpty) {
      return Response.json({'message': 'No OTP found for this email'}, 400);
    }

    final row = rows.first;
    final storedCode = row['code'].toString().trim().toUpperCase();
    final expiresAtRaw = row['expires_at'];
    final expiresAt = expiresAtRaw is DateTime
        ? expiresAtRaw
        : DateTime.tryParse(expiresAtRaw.toString());

    print('[OTP] Verify attempt for $email: entered=$code stored=$storedCode');

    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      await connection!.statement('DELETE FROM otps WHERE email = \$1', [email]);
      return Response.json({'message': 'OTP has expired'}, 400);
    }

    if (code != storedCode) {
      return Response.json({'message': 'Invalid OTP'}, 400);
    }

    // Valid — delete it so it can't be reused
    await connection!.statement('DELETE FROM otps WHERE email = \$1', [email]);

    return Response.json({
      'message': 'OTP verified successfully',
      'email': email,
    }, HttpStatus.ok);
  }

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

final OtpController otpController = OtpController();
