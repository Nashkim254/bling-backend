import 'package:vania/vania.dart';

class CreateAdminUserRolesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS admin_user_roles (
        id CHAR(36) PRIMARY KEY,
        user_id CHAR(36) NOT NULL,
        role_id CHAR(36) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
        UNIQUE(user_id, role_id)
      )
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement('DROP TABLE IF EXISTS admin_user_roles', []);
  }
}
