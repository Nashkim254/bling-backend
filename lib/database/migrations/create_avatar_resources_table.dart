import 'package:vania/vania.dart';

class CreateAvatarResourcesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS avatar_resources (
        id CHAR(36) PRIMARY KEY,
        name VARCHAR(160) NOT NULL,
        image_url TEXT NOT NULL DEFAULT '',
        price_bling INTEGER NOT NULL DEFAULT 0,
        is_paid INTEGER NOT NULL DEFAULT 0,
        owners_count INTEGER NOT NULL DEFAULT 0,
        eligible_blingers TEXT NOT NULL DEFAULT 'All / above level 2 etc',
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
    await connection!.statement('DROP TABLE IF EXISTS avatar_resources', []);
  }
}
