import 'package:vania/vania.dart';

class CreatePostsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('posts', () {
      uuid('id', unique: true);
      primary('id');
      uuid("user_id");
      char("post_type");
      string('caption', length: 500);
      json('hashtags');
      integer('likes', defaultValue: 0);
      integer('comments', defaultValue: 0);
      integer('shares', defaultValue: 0);
      integer('reposts', defaultValue: 0);
      integer('is_active', defaultValue: 1);
      string('image_url', length: 300);
      json('media', nullable: true);
      string('thumbnail_url', length: 500, nullable: true);
      string('video_url', length: 500, nullable: true);
      string('media_kind', length: 20, defaultValue: 'image');
      string('storage_bucket', length: 100, nullable: true);
      string('storage_path', length: 500, nullable: true);
      string('mime_type', length: 120, nullable: true);
      timeStamp("deleted_at", nullable: true); // ✅ Fixed typo
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('posts');
  }
}
