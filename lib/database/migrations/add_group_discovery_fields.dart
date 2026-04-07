import 'package:vania/vania.dart';

class AddGroupDiscoveryFields extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      'ALTER TABLE groups ADD COLUMN IF NOT EXISTS discoverable_country TEXT',
      [],
    );
    await connection!.statement(
      'ALTER TABLE groups ADD COLUMN IF NOT EXISTS discoverable_area TEXT',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      '''
      ALTER TABLE groups
      DROP COLUMN IF EXISTS discoverable_country,
      DROP COLUMN IF EXISTS discoverable_area
      ''',
      [],
    );
  }
}
