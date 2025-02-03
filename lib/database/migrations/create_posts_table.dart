import 'package:vania/vania.dart';

class CreatePostsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('posts', () {
      char('id');
      primary('id');
      char("user_id");
      char("type");
      char("caption");
      integer('likes');
      integer('comments');
      integer('shares');
      integer('reposts');
      integer('is_active');
      string('image_url');
      timeStamp("deleated_at", nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('posts');
  }
}
