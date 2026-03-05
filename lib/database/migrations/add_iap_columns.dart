import 'package:vania/vania.dart';

/// Adds IAP-related columns to existing tables.
/// - bling_packages.store_product_id  — the App Store / Play Store product ID
/// - bling_transactions.platform       — 'ios' | 'android' | 'simulated'
/// - bling_transactions.store_transaction_id — used for idempotency
class AddIapColumns extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      "ALTER TABLE bling_packages ADD COLUMN IF NOT EXISTS store_product_id VARCHAR(200)",
      [],
    );
    await connection!.statement(
      "ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS platform VARCHAR(20)",
      [],
    );
    await connection!.statement(
      "ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS store_transaction_id VARCHAR(500)",
      [],
    );
    // Unique index to prevent double-crediting the same store transaction
    await connection!.statement(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_store_transaction_id ON bling_transactions (store_transaction_id) WHERE store_transaction_id IS NOT NULL",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      "ALTER TABLE bling_packages DROP COLUMN IF EXISTS store_product_id",
      [],
    );
    await connection!.statement(
      "ALTER TABLE bling_transactions DROP COLUMN IF EXISTS platform",
      [],
    );
    await connection!.statement(
      "ALTER TABLE bling_transactions DROP COLUMN IF EXISTS store_transaction_id",
      [],
    );
  }
}
