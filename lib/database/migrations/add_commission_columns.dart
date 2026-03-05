import 'package:vania/vania.dart';

/// Adds commission-related columns to bling_transactions:
/// - context:    'direct' | 'post_tip' | 'challenge_tip'
/// - fee_amount: bling taken as platform commission (0 for direct transfers)
class AddCommissionColumns extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      "ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS context VARCHAR(50) DEFAULT 'direct'",
      [],
    );
    await connection!.statement(
      "ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS fee_amount INTEGER DEFAULT 0",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      "ALTER TABLE bling_transactions DROP COLUMN IF EXISTS context",
      [],
    );
    await connection!.statement(
      "ALTER TABLE bling_transactions DROP COLUMN IF EXISTS fee_amount",
      [],
    );
  }
}
