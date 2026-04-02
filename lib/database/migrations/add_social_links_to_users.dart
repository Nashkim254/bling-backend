import 'package:vania/vania.dart';

class AddSocialLinksToUsers extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      "ALTER TABLE users ADD COLUMN IF NOT EXISTS social_links TEXT DEFAULT '[]'",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      'ALTER TABLE users DROP COLUMN IF EXISTS social_links',
      [],
    );
  }
}
