import 'package:vania/vania.dart';

class AlterUsersAddFcmToken extends Migration {
  @override
  Future<void> up() async {
    await connection!.statement(
      "ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT",
      [],
    );
  }

  @override
  Future<void> down() async {
    await connection!.statement(
      "ALTER TABLE users DROP COLUMN IF EXISTS fcm_token",
      [],
    );
  }
}
