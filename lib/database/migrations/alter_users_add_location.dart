import 'package:vania/vania.dart';

class AlterUsersAddLocation extends Migration {
  @override
  Future<void> up() async {
    await connection!.statement(
      "ALTER TABLE users ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION",
      [],
    );
    await connection!.statement(
      "ALTER TABLE users ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION",
      [],
    );
  }

  @override
  Future<void> down() async {
    await connection!.statement(
      "ALTER TABLE users DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude",
      [],
    );
  }
}
