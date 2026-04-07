import 'package:vania/vania.dart';

class AddPriceToAdminLevelMedals extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      ALTER TABLE admin_level_medals
      ADD COLUMN IF NOT EXISTS price_bling INTEGER NOT NULL DEFAULT 0
      ''',
      [],
    );

    await connection!.statement(
      '''
      ALTER TABLE admin_level_medals
      ADD COLUMN IF NOT EXISTS is_paid INTEGER NOT NULL DEFAULT 0
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'ALTER TABLE admin_level_medals DROP COLUMN IF EXISTS is_paid',
      [],
    );
    await connection!.statement(
      'ALTER TABLE admin_level_medals DROP COLUMN IF EXISTS price_bling',
      [],
    );
  }
}
