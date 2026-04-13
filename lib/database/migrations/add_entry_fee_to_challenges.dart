import 'package:vania/vania.dart';

class AddEntryFeeToChallenges extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      '''
      ALTER TABLE challenges
      ADD COLUMN IF NOT EXISTS entry_fee_bling INTEGER NOT NULL DEFAULT 0
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'ALTER TABLE challenges DROP COLUMN IF EXISTS entry_fee_bling',
      [],
    );
  }
}
