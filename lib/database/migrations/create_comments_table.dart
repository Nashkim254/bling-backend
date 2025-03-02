import 'package:vania/vania.dart';

class CreateCommentsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('comments', () {
      uuid('id');
      primary('id');
      uuid("user_id");
      uuid("post_id");
      string("comment");
      timeStamp('expires_at', nullable: true);
      timeStamp("deleted_at", nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('comments');
  }
}
