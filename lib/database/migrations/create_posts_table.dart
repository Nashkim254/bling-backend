import 'package:vania/vania.dart';

class CreatePostsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('posts', () {
      char('id', unique: true);
      primary('id');
      char("user_id");
      char("type");
      char("caption");
      json('hashtags');
      integer('likes', defaultValue: 0);
      integer('comments', defaultValue: 0);
      integer('shares', defaultValue: 0);
      integer('reposts', defaultValue: 0);
      integer('is_active', defaultValue: 1);
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
