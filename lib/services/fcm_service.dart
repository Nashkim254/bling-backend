import 'dart:convert';
import 'dart:io';

import 'package:bling/app/models/user.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

/// Firebase Cloud Messaging HTTP v1 API wrapper.
/// Set FIREBASE_PROJECT_ID and FIREBASE_SERVICE_ACCOUNT_JSON in .env
class FcmService {
  static final FcmService instance = FcmService._();
  FcmService._();

  String get _projectId => Platform.environment['FIREBASE_PROJECT_ID'] ?? '';
  String get _saJson =>
      Platform.environment['FIREBASE_SERVICE_ACCOUNT_JSON'] ?? '';

  String? _accessToken;
  DateTime? _tokenExpiry;

  /// Returns a valid OAuth2 access token, refreshing if needed.
  Future<String?> _getAccessToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    if (_saJson.isEmpty || _projectId.isEmpty) {
      print('[FCM] FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_PROJECT_ID not set');
      return null;
    }

    try {
      final sa = jsonDecode(_saJson) as Map<String, dynamic>;
      final clientEmail = sa['client_email'] as String;
      final privateKey = sa['private_key'] as String;

      final now = DateTime.now();
      final jwt = JWT(
        {
          'iss': clientEmail,
          'scope': 'https://www.googleapis.com/auth/firebase.messaging',
          'aud': 'https://oauth2.googleapis.com/token',
          'iat': now.millisecondsSinceEpoch ~/ 1000,
          'exp': (now.millisecondsSinceEpoch ~/ 1000) + 3600,
        },
      );

      final signed = jwt.sign(
        RSAPrivateKey(privateKey),
        algorithm: JWTAlgorithm.RS256,
      );

      final res = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': signed,
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String;
        _tokenExpiry = now.add(const Duration(seconds: 3500));
        return _accessToken;
      }

      print('[FCM] Token exchange failed: ${res.body}');
      return null;
    } catch (e) {
      print('[FCM] _getAccessToken error: $e');
      return null;
    }
  }

  /// Send to a specific device token.
  Future<void> sendToToken(
    String fcmToken, {
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    final token = await _getAccessToken();
    if (token == null) return;

    try {
      final res = await http.post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': {
            'token': fcmToken,
            'notification': {'title': title, 'body': body},
            if (data.isNotEmpty) 'data': data,
            'android': {'priority': 'high'},
            'apns': {
              'headers': {'apns-priority': '10'}
            },
          }
        }),
      );

      if (res.statusCode != 200) {
        print('[FCM] Send failed (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      print('[FCM] sendToToken error: $e');
    }
  }

  /// Lookup user's fcm_token then send.
  Future<void> sendToUser(
    String userId, {
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      final user = await User()
          .query()
          .select(['fcm_token'])
          .where('id', '=', userId)
          .first();
      final fcmToken = user?['fcm_token'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) return;
      await sendToToken(fcmToken, title: title, body: body, data: data);
    } catch (e) {
      print('[FCM] sendToUser error: $e');
    }
  }

  /// Send to multiple users (batch — one request each, runs concurrently).
  Future<void> sendToUsers(
    List<String> userIds, {
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    await Future.wait(
      userIds.map((id) => sendToUser(id, title: title, body: body, data: data)),
    );
  }
}
