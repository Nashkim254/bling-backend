import 'dart:convert';
import 'dart:math';

class ContentEmbeddingService {
  ContentEmbeddingService._();

  static final ContentEmbeddingService instance = ContentEmbeddingService._();

  static const int vectorSize = 256;

  List<double> embedPost({
    required String caption,
    required String postType,
    required List<String> hashtags,
    required String mediaKind,
  }) {
    final vector = List<double>.filled(vectorSize, 0);
    final parts = <String>[
      caption,
      postType,
      mediaKind,
      ...hashtags,
    ];

    for (final part in parts) {
      for (final token in _tokenize(part)) {
        final hash = token.hashCode;
        final index = hash.abs() % vectorSize;
        final sign = hash.isEven ? 1.0 : -1.0;
        final magnitude = 1.0 + ((hash.abs() % 100) / 250.0);
        vector[index] += sign * magnitude;
      }
    }

    return _normalize(vector);
  }

  List<String> parseHashtags(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return const [];

    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Fall back to regex extraction below.
    }

    return RegExp(r'#\w+')
        .allMatches(text)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Iterable<String> _tokenize(String value) sync* {
    final normalized = value.toLowerCase();
    for (final raw in normalized.split(RegExp(r'[^a-z0-9#]+'))) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      yield token;
      if (token.startsWith('#') && token.length > 1) {
        yield token.substring(1);
      }
    }
  }

  List<double> _normalize(List<double> vector) {
    var sum = 0.0;
    for (final value in vector) {
      sum += value * value;
    }
    final norm = sqrt(sum);
    if (norm == 0) return vector;
    return vector.map((value) => value / norm).toList();
  }
}
