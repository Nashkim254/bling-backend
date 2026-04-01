import 'package:vania/vania.dart';

class AddAdminTransactionColumns extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      "ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS admin_status VARCHAR(20) DEFAULT 'complete' NOT NULL",
      [],
    );
    await connection!.statement(
      'ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS reversed_by CHAR(36) NULL',
      [],
    );
    await connection!.statement(
      'ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS reversed_at TIMESTAMP NULL',
      [],
    );
    await connection!.statement(
      "ALTER TABLE bling_transactions ADD COLUMN IF NOT EXISTS reverse_reason TEXT NOT NULL DEFAULT ''",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    for (final column in [
      'admin_status',
      'reversed_by',
      'reversed_at',
      'reverse_reason',
    ]) {
      await connection!.statement(
        'ALTER TABLE bling_transactions DROP COLUMN IF EXISTS $column',
        [],
      );
    }
  }
}
