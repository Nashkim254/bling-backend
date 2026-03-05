import 'package:vania/vania.dart';

class AlterCommentsAddParentId extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      "ALTER TABLE comments ADD COLUMN IF NOT EXISTS parent_id VARCHAR(255)",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      "ALTER TABLE comments DROP COLUMN IF EXISTS parent_id",
      [],
    );
  }
}
