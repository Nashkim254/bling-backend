import 'package:vania/vania.dart';

class OtpMail {
  final String to;
  final String code;
  final DateTime expiresAt;
  final String type;

  const OtpMail({
    required this.to,
    required this.code,
    required this.expiresAt,
    required this.type,
  });

  String get fromAddress =>
      env('RESEND_FROM_EMAIL', 'onboarding@resend.dev') ??
      'onboarding@resend.dev';

  String get fromName => env('RESEND_FROM_NAME', env('APP_NAME', 'Bling')) ??
      env('APP_NAME', 'Bling') ??
      'Bling';

  String get subject => type == 'registration'
      ? 'Your Bling registration code'
      : 'Your Bling password reset code';

  String get text {
    final expiresInMinutes = expiresAt.difference(DateTime.now()).inMinutes;
    final purpose = type == 'registration'
        ? 'complete your Bling account registration'
        : 'continue your Bling account recovery';

    return 'Your Bling verification code is $code.\n\n'
        'Use this code to $purpose.\n'
        'This code expires in ${expiresInMinutes.clamp(0, 10)} minutes.\n\n'
        'If you did not request this code, you can ignore this email.';
  }
}
