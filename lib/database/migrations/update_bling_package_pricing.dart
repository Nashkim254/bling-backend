import 'package:vania/vania.dart';

/// Aligns existing package amounts and prices with the premium production ladder.
class UpdateBlingPackagePricing extends Migration {
  @override
  Future<void> up() async {
    super.up();

    const updates = {
      'social.blingsocial.app.starter': {'name': 'Starter', 'bling': 100, 'price': 499},
      'social.blingsocial.app.basic': {'name': 'Basic', 'bling': 250, 'price': 999},
      'social.blingsocial.app.popular': {'name': 'Popular', 'bling': 700, 'price': 2499},
      'social.blingsocial.app.premium': {'name': 'Premium', 'bling': 1500, 'price': 4999},
      'social.blingsocial.app.elite': {'name': 'Elite', 'bling': 4000, 'price': 9999},
    };

    for (final entry in updates.entries) {
      await connection!.statement(
        'UPDATE bling_packages SET name = \$1, bling_amount = \$2, price_cents = \$3, updated_at = NOW() WHERE store_product_id = \$4',
        [
          entry.value['name'],
          entry.value['bling'],
          entry.value['price'],
          entry.key,
        ],
      );
    }
  }

  @override
  Future<void> down() async {
    super.down();

    const updates = {
      'social.blingsocial.app.starter': {'name': 'Starter', 'bling': 100, 'price': 99},
      'social.blingsocial.app.basic': {'name': 'Basic', 'bling': 500, 'price': 399},
      'social.blingsocial.app.popular': {'name': 'Popular', 'bling': 1200, 'price': 799},
      'social.blingsocial.app.premium': {'name': 'Premium', 'bling': 3000, 'price': 1499},
      'social.blingsocial.app.elite': {'name': 'Elite', 'bling': 10000, 'price': 3999},
    };

    for (final entry in updates.entries) {
      await connection!.statement(
        'UPDATE bling_packages SET name = \$1, bling_amount = \$2, price_cents = \$3, updated_at = NOW() WHERE store_product_id = \$4',
        [
          entry.value['name'],
          entry.value['bling'],
          entry.value['price'],
          entry.key,
        ],
      );
    }
  }
}
