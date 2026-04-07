import 'package:vania/vania.dart';

class CreateUserMedalInventoryTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS user_medal_inventory (
        id CHAR(36) PRIMARY KEY,
        user_id CHAR(36) NOT NULL,
        medal_id CHAR(36) NOT NULL,
        purchased_at TIMESTAMP NOT NULL DEFAULT NOW(),
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
        UNIQUE(user_id, medal_id)
      )
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!
        .statement('DROP TABLE IF EXISTS user_medal_inventory', []);
  }
}
