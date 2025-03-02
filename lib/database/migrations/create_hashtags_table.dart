import 'package:vania/vania.dart';

class CreateHashtagsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('hashtags', () {
      uuid('id');
      primary('id');
      json('hashtags');
      uuid("user_id");
      uuid("post_id");
      timeStamp("deleated_at", nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('hashtags');
  }
}
