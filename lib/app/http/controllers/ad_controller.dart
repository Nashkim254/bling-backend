import 'dart:io';

import 'package:bling/app/models/ad.dart';
import 'package:vania/vania.dart';

class AdController extends Controller {
  /// GET /api/ads?count=1  (returns random active ads for feed injection)
  Future<Response> getAds(Request request) async {
    final count =
        int.tryParse(request.input('count')?.toString() ?? '1') ?? 1;

    try {
      final ads = await Ad()
          .query()
          .where('is_active', '=', 1)
          .orderByRaw('RANDOM()')
          .limit(count)
          .get();

      return Response.json({
        'ads': (ads as List).map((ad) => {
              'id': ad['id'],
              'title': ad['title'],
              'body': ad['body'],
              'image_url': ad['image_url'],
              'target_url': ad['target_url'],
              'item_type': 'ad',
            }).toList(),
      }, HttpStatus.ok);
    } catch (e) {
      return Response.json({'ads': []}, HttpStatus.ok);
    }
  }
}

final AdController adController = AdController();
