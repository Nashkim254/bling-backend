import 'package:vania/vania.dart';

class CreateAdminLeaderboardsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS admin_leaderboards (
        id CHAR(36) PRIMARY KEY,
        name VARCHAR(160) NOT NULL,
        metric VARCHAR(40) NOT NULL DEFAULT 'bling',
        users_limit INTEGER NOT NULL DEFAULT 20,
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
    await connection!.statement('DROP TABLE IF EXISTS admin_leaderboards', []);
  }
}
