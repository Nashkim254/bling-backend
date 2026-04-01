import 'package:vania/vania.dart';

class CreateAdminRolesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS admin_roles (
        id CHAR(36) PRIMARY KEY,
        name VARCHAR(120) UNIQUE NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        permissions TEXT NOT NULL DEFAULT '[]',
        status VARCHAR(20) NOT NULL DEFAULT 'active',
        created_by CHAR(36) NULL,
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
    await connection!.statement('DROP TABLE IF EXISTS admin_roles', []);
  }
}
