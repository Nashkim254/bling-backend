import 'package:vania/vania.dart';

class RequestData {
  RequestData(this._request)
      : _body = _request.body is Map
            ? Map<String, dynamic>.from(_request.body as Map)
            : const <String, dynamic>{};

  final Request _request;
  final Map<String, dynamic> _body;

  Map<String, dynamic> get body => _body;

  dynamic value(String key) => _request.input(key) ?? _body[key];

  bool has(String key) {
    final candidate = value(key);
    if (candidate == null) return false;
    if (candidate is String) return candidate.trim().isNotEmpty;
    return true;
  }

  String string(String key, {String fallback = ''}) {
    final candidate = value(key);
    if (candidate == null) return fallback;
    return candidate.toString();
  }

  String trimmed(String key, {String fallback = ''}) {
    return string(key, fallback: fallback).trim();
  }

  String lower(String key, {String fallback = ''}) {
    return trimmed(key, fallback: fallback).toLowerCase();
  }

  String upper(String key, {String fallback = ''}) {
    return trimmed(key, fallback: fallback).toUpperCase();
  }

  int? intValue(String key) {
    final candidate = value(key);
    if (candidate is int) return candidate;
    if (candidate is num) return candidate.toInt();
    return int.tryParse(candidate?.toString() ?? '');
  }

  double? doubleValue(String key) {
    final candidate = value(key);
    if (candidate is double) return candidate;
    if (candidate is num) return candidate.toDouble();
    return double.tryParse(candidate?.toString() ?? '');
  }

  bool boolValue(String key, {bool fallback = false}) {
    final candidate = value(key);
    if (candidate is bool) return candidate;
    if (candidate is num) return candidate != 0;
    final text = candidate?.toString().trim().toLowerCase() ?? '';
    if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
      return false;
    }
    return fallback;
  }

  List<dynamic> list(String key) {
    final candidate = value(key);
    if (candidate is List) return candidate;
    return const [];
  }

  Map<String, dynamic> map(String key) {
    final candidate = value(key);
    if (candidate is Map) {
      return Map<String, dynamic>.from(candidate);
    }
    return const <String, dynamic>{};
  }

  Map<String, String> require(Map<String, String> rules) {
    final errors = <String, String>{};
    for (final entry in rules.entries) {
      if (!has(entry.key)) {
        errors[entry.key] = entry.value;
      }
    }
    return errors;
  }
}
