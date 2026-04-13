import 'package:vania/vania.dart';

class AddJudgingTypeToChallenges extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      '''
      ALTER TABLE challenges
      ADD COLUMN IF NOT EXISTS judging_type VARCHAR(30) NOT NULL DEFAULT 'hybrid'
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'ALTER TABLE challenges DROP COLUMN IF EXISTS judging_type',
      [],
    );
  }
}
