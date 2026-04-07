import 'package:vania/vania.dart';

class AddCategoryToAvatarAccessories extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      "ALTER TABLE avatar_accessories ADD COLUMN IF NOT EXISTS category VARCHAR(20) NOT NULL DEFAULT 'accessory'",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'ALTER TABLE avatar_accessories DROP COLUMN IF EXISTS category',
      [],
    );
  }
}
