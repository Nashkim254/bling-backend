import 'package:vania/vania.dart';

class AddLocationTargetingToAds extends Migration {
  @override
  Future<void> up() async {
    final columns = <String, String>{
      'target_continent': 'TEXT',
      'target_country': 'TEXT',
      'target_country_code': 'VARCHAR(8)',
      'target_city': 'TEXT',
    };

    for (final entry in columns.entries) {
      await connection!.statement(
        'ALTER TABLE ads ADD COLUMN IF NOT EXISTS ${entry.key} ${entry.value}',
        [],
      );
    }

    await connection!.statement(
      'CREATE INDEX IF NOT EXISTS idx_ads_location_targeting ON ads (target_continent, target_country_code, target_city)',
      [],
    );
  }

  @override
  Future<void> down() async {
    await connection!.statement(
      '''
      ALTER TABLE ads
      DROP COLUMN IF EXISTS target_continent,
      DROP COLUMN IF EXISTS target_country,
      DROP COLUMN IF EXISTS target_country_code,
      DROP COLUMN IF EXISTS target_city
      ''',
      [],
    );
  }
}
