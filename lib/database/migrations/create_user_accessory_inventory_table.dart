import 'package:vania/vania.dart';

class CreateUserAccessoryInventoryTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS user_accessory_inventory (
        id CHAR(36) PRIMARY KEY,
        user_id CHAR(36) NOT NULL,
        accessory_id CHAR(36) NOT NULL,
        is_equipped INTEGER NOT NULL DEFAULT 0,
        purchased_at TIMESTAMP NOT NULL DEFAULT NOW(),
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'DROP TABLE IF EXISTS user_accessory_inventory',
      [],
    );
  }
}
