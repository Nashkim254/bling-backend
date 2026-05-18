import 'package:vania/vania.dart';

class AddLocationProfileFieldsToUsers extends Migration {
  @override
  Future<void> up() async {
    final columns = <String, String>{
      'city': 'TEXT',
      'region': 'TEXT',
      'country': 'TEXT',
      'country_code': 'VARCHAR(8)',
      'continent': 'TEXT',
      'location_updated_at': 'TIMESTAMP',
    };

    for (final entry in columns.entries) {
      await connection!.statement(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS ${entry.key} ${entry.value}',
        [],
      );
    }

    await connection!.statement(
      'CREATE INDEX IF NOT EXISTS idx_users_location_scope ON users (continent, country_code, city)',
      [],
    );
  }

  @override
  Future<void> down() async {
    await connection!.statement(
      '''
      ALTER TABLE users
      DROP COLUMN IF EXISTS city,
      DROP COLUMN IF EXISTS region,
      DROP COLUMN IF EXISTS country,
      DROP COLUMN IF EXISTS country_code,
      DROP COLUMN IF EXISTS continent,
      DROP COLUMN IF EXISTS location_updated_at
      ''',
      [],
    );
  }
}
