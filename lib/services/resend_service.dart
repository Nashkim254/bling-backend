import 'dart:convert';
import 'dart:io';

import 'package:bling/app/mail/otp_mail.dart';
import 'package:http/http.dart' as http;
import 'package:vania/vania.dart';

class ResendService {
  static final ResendService instance = ResendService._();

  ResendService._();

  String get _apiKey =>
      (Platform.environment['RESEND_API_KEY'] ?? env('RESEND_API_KEY', '') ?? '')
          .trim();

  Future<void> sendOtpMail(OtpMail mail) async {
    if (_apiKey.isEmpty) {
      throw Exception('RESEND_API_KEY is not configured');
    }

    final response = await http
        .post(
          Uri.parse('https://api.resend.com/emails'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'from': '${mail.fromName} <${mail.fromAddress}>',
            'to': [mail.to],
            'subject': mail.subject,
            'text': mail.text,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Resend API failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}
