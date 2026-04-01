import 'package:vania/vania.dart';

class CreateAdminNotificationCasesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS admin_notification_cases (
        id CHAR(36) PRIMARY KEY,
        notification_id CHAR(36) NOT NULL UNIQUE,
        status VARCHAR(20) NOT NULL DEFAULT 'pending',
        notes TEXT NOT NULL DEFAULT '',
        processed_by CHAR(36) NULL,
        processed_at TIMESTAMP NULL,
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
    await connection!.statement(
      'DROP TABLE IF EXISTS admin_notification_cases',
      [],
    );
  }
}
