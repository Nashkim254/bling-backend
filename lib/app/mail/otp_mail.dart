import 'package:vania/vania.dart';

class OtpMail extends Mailable {
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

  @override
  List<Attachment>? attachments() => null;

  @override
  Content content() {
    final expiresInMinutes = expiresAt.difference(DateTime.now()).inMinutes;
    final purpose = type == 'registration'
        ? 'complete your Bling account registration'
        : 'continue your Bling account recovery';

    return Content(
      text:
          'Your Bling verification code is $code.\n\n'
          'Use this code to $purpose.\n'
          'This code expires in ${expiresInMinutes.clamp(0, 10)} minutes.\n\n'
          'If you did not request this code, you can ignore this email.',
    );
  }

  @override
  Envelope envelope() {
    final fromAddress = env('MAIL_FROM_ADDRESS', 'no-reply@blingsocial.social');
    final fromName = env('MAIL_FROM_NAME', env('APP_NAME', 'Bling'));
    final subject = type == 'registration'
        ? 'Your Bling registration code'
        : 'Your Bling password reset code';

    return Envelope(
      from: Address(fromAddress, fromName),
      to: [Address(to)],
      subject: subject,
    );
  }
}
