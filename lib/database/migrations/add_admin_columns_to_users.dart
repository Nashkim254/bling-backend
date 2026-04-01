import 'package:vania/vania.dart';

class AddAdminColumnsToUsers extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin INTEGER DEFAULT 0 NOT NULL",
      [],
    );

    final adminCountRows = await connection!.select(
      'SELECT COUNT(*) AS cnt FROM users WHERE is_admin = 1',
      [],
    );
    final adminCount = (adminCountRows.first['cnt'] as num?)?.toInt() ?? 0;

    if (adminCount == 0) {
      await connection!.statement(
        '''
        UPDATE users
        SET is_admin = 1, updated_at = NOW()
        WHERE id = (
          SELECT id FROM users
          WHERE deleted_at IS NULL
          ORDER BY created_at ASC
          LIMIT 1
        )
        ''',
        [],
      );
    }
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'ALTER TABLE users DROP COLUMN IF EXISTS is_admin',
      [],
    );
  }
}
