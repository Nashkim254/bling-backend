import 'package:vania/vania.dart';

class CreateAdminLevelsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS admin_levels (
        id CHAR(36) PRIMARY KEY,
        level_number INTEGER NOT NULL,
        name VARCHAR(120) NOT NULL,
        required_bling INTEGER NOT NULL DEFAULT 0,
        status VARCHAR(20) NOT NULL DEFAULT 'active',
        created_by CHAR(36) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
        UNIQUE(level_number)
      )
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement('DROP TABLE IF EXISTS admin_levels', []);
  }
}
