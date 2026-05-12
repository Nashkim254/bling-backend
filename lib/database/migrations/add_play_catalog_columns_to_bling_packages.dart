import 'package:vania/vania.dart';

class AddPlayCatalogColumnsToBlingPackages extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_title TEXT",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_description TEXT",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_language VARCHAR(20)",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_purchase_option_id VARCHAR(100)",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_formatted_price VARCHAR(50)",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_price_currency_code VARCHAR(12)",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_price_micros BIGINT",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_offer_tags TEXT",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS play_synced_at TIMESTAMP",
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_synced_at",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_offer_tags",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_price_micros",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_price_currency_code",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_formatted_price",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_purchase_option_id",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_language",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_description",
    );
    await connection!.execute(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS play_title",
    );
  }
}
