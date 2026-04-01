import 'package:vania/vania.dart';

class CreateAdminLevelMedalsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS admin_level_medals (
        id CHAR(36) PRIMARY KEY,
        level_id CHAR(36) NOT NULL,
        name VARCHAR(160) NOT NULL,
        metric_label VARCHAR(120) NOT NULL DEFAULT '',
        image_url TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
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
    await connection!.statement('DROP TABLE IF EXISTS admin_level_medals', []);
  }
}
