import 'package:vania/vania.dart';

class AlterUsersAddStatus extends Migration {
  @override
  Future<void> up() async {
    super.up();
    // 'active' | 'disabled' | 'deleted'
    await connection!.statement(
      "ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'active' NOT NULL",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'ALTER TABLE users DROP COLUMN IF EXISTS status',
      [],
    );
  }
}
