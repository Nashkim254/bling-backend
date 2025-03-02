import 'package:vania/vania.dart';

class CreateSharesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('shares', () {
      uuid('id');
      primary('id');
      uuid("user_id");
      uuid("post_id");
      timeStamp('expires_at', nullable: true);
      timeStamp("deleted_at", nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('shares');
  }
}
