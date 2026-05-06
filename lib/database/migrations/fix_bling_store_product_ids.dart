import 'package:vania/vania.dart';

/// Replaces old placeholder Play product IDs with the production package IDs.
class FixBlingStoreProductIds extends Migration {
  @override
  Future<void> up() async {
    super.up();

    const updates = {
      'com.example.bling.starter': 'social.blingsocial.app.starter',
      'com.example.bling.basic': 'social.blingsocial.app.basic',
      'com.example.bling.popular': 'social.blingsocial.app.popular',
      'com.example.bling.premium': 'social.blingsocial.app.premium',
      'com.example.bling.elite': 'social.blingsocial.app.elite',
    };

    for (final entry in updates.entries) {
      await connection!.statement(
        'UPDATE bling_packages SET store_product_id = \$1, updated_at = NOW() WHERE store_product_id = \$2',
        [entry.value, entry.key],
      );
    }
  }

  @override
  Future<void> down() async {
    super.down();

    const updates = {
      'social.blingsocial.app.starter': 'com.example.bling.starter',
      'social.blingsocial.app.basic': 'com.example.bling.basic',
      'social.blingsocial.app.popular': 'com.example.bling.popular',
      'social.blingsocial.app.premium': 'com.example.bling.premium',
      'social.blingsocial.app.elite': 'com.example.bling.elite',
    };

    for (final entry in updates.entries) {
      await connection!.statement(
        'UPDATE bling_packages SET store_product_id = \$1, updated_at = NOW() WHERE store_product_id = \$2',
        [entry.value, entry.key],
      );
    }
  }
}
