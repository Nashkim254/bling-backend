import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vania/vania.dart';

class GooglePlayCatalogService {
  static const Duration _requestTimeout = Duration(seconds: 20);

  bool get isConfigured =>
      _serviceAccountJson.trim().isNotEmpty && _packageName.trim().isNotEmpty;

  String get _serviceAccountJson =>
      Platform.environment['GOOGLE_SERVICE_ACCOUNT_JSON'] ?? '';

  String get _packageName =>
      Platform.environment['GOOGLE_PLAY_PACKAGE_NAME'] ?? '';

  String get _defaultLanguage {
    final value =
        Platform.environment['GOOGLE_PLAY_DEFAULT_LANGUAGE'] ?? 'en-US';
    return value.trim().isEmpty ? 'en-US' : value.trim();
  }

  String get _defaultRegion {
    final value = Platform.environment['GOOGLE_PLAY_DEFAULT_REGION'] ?? 'KE';
    return value.trim().isEmpty ? 'KE' : value.trim().toUpperCase();
  }

  Duration get _syncTtl {
    final raw = Platform.environment['GOOGLE_PLAY_CATALOG_TTL_MINUTES'] ?? '';
    final minutes = int.tryParse(raw) ?? 360;
    return Duration(minutes: minutes < 5 ? 5 : minutes);
  }

  Future<bool> syncPackagesIfStale() async {
    if (!isConfigured) return false;

    final rows = await connection!.select(
      'SELECT id, store_product_id, updated_at, play_synced_at '
      'FROM bling_packages WHERE is_active = 1',
      [],
    );

    final packages = rows.whereType<Map>().toList();
    if (packages.isEmpty) return false;

    final now = DateTime.now();
    final shouldSync = packages.any((row) {
      final syncedAt =
          DateTime.tryParse(row['play_synced_at']?.toString() ?? '');
      if (syncedAt == null) return true;
      return now.difference(syncedAt) > _syncTtl;
    });

    if (!shouldSync) return false;
    return syncPackages();
  }

  Future<bool> syncPackages() async {
    if (!isConfigured) return false;

    final rows = await connection!.select(
      'SELECT id, name, bling_amount, price_cents, store_product_id '
      'FROM bling_packages WHERE is_active = 1 AND store_product_id IS NOT NULL AND store_product_id <> \'\'',
      [],
    );

    final packages = rows.whereType<Map>().toList();
    if (packages.isEmpty) return false;

    final accessToken = await _getGoogleAccessToken(_serviceAccountJson);
    if (accessToken == null || accessToken.isEmpty) {
      return false;
    }

    var updatedAny = false;
    for (final package in packages) {
      final productId = package['store_product_id']?.toString() ?? '';
      if (productId.isEmpty) continue;

      final data = await _fetchOneTimeProduct(
        accessToken: accessToken,
        productId: productId,
      );
      if (data == null) continue;

      final listing = _pickListing(data['listings']);
      final purchaseOption = _pickPurchaseOption(data['purchaseOptions']);
      final regionalPrice = _pickRegionalPrice(
        purchaseOption?['regionalPricingAndAvailabilityConfigs'],
      );

      final priceMicros = _microsFromRegionalPrice(regionalPrice);
      final formattedPrice = _formattedPrice(regionalPrice, priceMicros);

      await connection!.execute(
        'UPDATE bling_packages '
        'SET play_title = \$1, '
        'play_description = \$2, '
        'play_language = \$3, '
        'play_purchase_option_id = \$4, '
        'play_formatted_price = \$5, '
        'play_price_currency_code = \$6, '
        'play_price_micros = \$7, '
        'play_offer_tags = \$8, '
        'play_synced_at = NOW(), '
        'updated_at = NOW() '
        'WHERE id = \$9',
        [
          listing?['title']?.toString() ?? package['name']?.toString() ?? '',
          listing?['description']?.toString() ?? '',
          listing?['languageCode']?.toString() ?? _defaultLanguage,
          purchaseOption?['purchaseOptionId']?.toString() ?? '',
          formattedPrice,
          _currencyCode(regionalPrice),
          priceMicros,
          jsonEncode(_extractOfferTags(purchaseOption)),
          package['id'],
        ],
      );
      updatedAny = true;
    }

    return updatedAny;
  }

  Future<Map<String, dynamic>?> _fetchOneTimeProduct({
    required String accessToken,
    required String productId,
  }) async {
    try {
      final uri = Uri.parse(
        'https://androidpublisher.googleapis.com/androidpublisher/v3'
        '/applications/$_packageName/oneTimeProducts/$productId',
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return body;
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _pickListing(dynamic rawListings) {
    if (rawListings is! List) return null;
    final listings = rawListings.whereType<Map>().map(_mapify).toList();
    if (listings.isEmpty) return null;

    for (final listing in listings) {
      if ((listing['languageCode']?.toString() ?? '') == _defaultLanguage) {
        return listing;
      }
    }
    return listings.first;
  }

  Map<String, dynamic>? _pickPurchaseOption(dynamic rawPurchaseOptions) {
    if (rawPurchaseOptions is! List) return null;
    final options = rawPurchaseOptions.whereType<Map>().map(_mapify).toList();
    if (options.isEmpty) return null;

    for (final option in options) {
      final state = option['state']?.toString().toUpperCase() ?? '';
      final buyOption = _mapify(option['buyOption']);
      final legacyCompatible =
          buyOption['legacyCompatible'] == true || buyOption.isEmpty;
      if ((state.isEmpty || state == 'ACTIVE') &&
          buyOption.isNotEmpty &&
          legacyCompatible) {
        return option;
      }
    }

    for (final option in options) {
      final state = option['state']?.toString().toUpperCase() ?? '';
      final buyOption = _mapify(option['buyOption']);
      if ((state.isEmpty || state == 'ACTIVE') && buyOption.isNotEmpty) {
        return option;
      }
    }

    return options.firstWhere(
      (option) => _mapify(option['buyOption']).isNotEmpty,
      orElse: () => options.first,
    );
  }

  Map<String, dynamic>? _pickRegionalPrice(dynamic rawRegionalPrices) {
    if (rawRegionalPrices is! List) return null;
    final prices = rawRegionalPrices.whereType<Map>().map(_mapify).toList();
    if (prices.isEmpty) return null;

    for (final price in prices) {
      final regionCode = price['regionCode']?.toString().toUpperCase() ?? '';
      final availability =
          price['availability']?.toString().toUpperCase() ?? 'AVAILABLE';
      if (regionCode == _defaultRegion && availability == 'AVAILABLE') {
        return price;
      }
    }
    for (final price in prices) {
      final availability =
          price['availability']?.toString().toUpperCase() ?? 'AVAILABLE';
      if (availability == 'AVAILABLE') return price;
    }
    return prices.first;
  }

  int? _microsFromRegionalPrice(Map<String, dynamic>? regionalPrice) {
    if (regionalPrice == null) return null;
    final price = _mapify(regionalPrice['price']);
    final units = int.tryParse(price['units']?.toString() ?? '0') ?? 0;
    final nanos = int.tryParse(price['nanos']?.toString() ?? '0') ?? 0;
    return (units * 1000000) + (nanos ~/ 1000);
  }

  String _currencyCode(Map<String, dynamic>? regionalPrice) {
    if (regionalPrice == null) return '';
    final price = _mapify(regionalPrice['price']);
    return price['currencyCode']?.toString() ?? '';
  }

  String? _formattedPrice(
    Map<String, dynamic>? regionalPrice,
    int? micros,
  ) {
    if (regionalPrice == null || micros == null) return null;
    final currency = _currencyCode(regionalPrice);
    if (currency.isEmpty) return null;
    final amount = micros / 1000000;
    return '${currency.toUpperCase()} ${amount.toStringAsFixed(2)}';
  }

  List<String> _extractOfferTags(Map<String, dynamic>? purchaseOption) {
    if (purchaseOption == null) return const [];
    final result = <String>[];
    final tags = purchaseOption['offerTags'];
    if (tags is List) {
      for (final tag in tags) {
        final map = _mapify(tag);
        final value = map['tag']?.toString() ?? map['name']?.toString() ?? '';
        if (value.trim().isNotEmpty) {
          result.add(value.trim());
        }
      }
    }
    return result;
  }

  Map<String, dynamic> _mapify(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }
    return const <String, dynamic>{};
  }

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
      await keyFile.writeAsString(privateKeyPem);
      await dataFile.writeAsString(signingInput);

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
        return null;
      }

      final sigBytes = await sigFile.readAsBytes();
      final sig = base64Url.encode(sigBytes).replaceAll('=', '');
      final jwt = '$signingInput.$sig';

      final tokenResp = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': jwt,
        },
      ).timeout(_requestTimeout);

      final tokenData = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      return tokenData['access_token'] as String?;
    } catch (_) {
      return null;
    } finally {
      for (final file in [keyFile, dataFile, sigFile]) {
        file.delete().catchError((dynamic _) => file);
      }
    }
  }
}
