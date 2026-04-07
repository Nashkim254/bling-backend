import 'package:vania/vania.dart';

class CreateUserAvatarInventoryTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS user_avatar_inventory (
        id CHAR(36) PRIMARY KEY,
        user_id CHAR(36) NOT NULL,
        avatar_id CHAR(36) NOT NULL,
        is_equipped INTEGER NOT NULL DEFAULT 0,
        purchased_at TIMESTAMP NOT NULL DEFAULT NOW(),
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
        UNIQUE(user_id, avatar_id)
      )
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!
        .statement('DROP TABLE IF EXISTS user_avatar_inventory', []);
  }
}
