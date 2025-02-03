import 'package:vania/vania.dart';

class CreateCommentsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('comments', () {
      char('id');
      primary('id');
      char("user_id");
      char("post_id");
      string("comment");
      timeStamp('expires_at', nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('comments');
  }
}
