import 'package:vania/vania.dart';

class AddEquippedCustomizationToUsers extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS equipped_avatar_id CHAR(36)',
      [],
    );
    await connection!.statement(
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS equipped_outfit_id CHAR(36)',
      [],
    );
    await connection!.statement(
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS equipped_accessory_id CHAR(36)',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      '''
      ALTER TABLE users
      DROP COLUMN IF EXISTS equipped_avatar_id,
      DROP COLUMN IF EXISTS equipped_outfit_id,
      DROP COLUMN IF EXISTS equipped_accessory_id
      ''',
      [],
    );
  }
}
