import 'package:vania/vania.dart';

class CreateHashtagsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('hashtags', () {
      char('id');
      primary('id');
      char("user_id");
      char("post_id");
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
