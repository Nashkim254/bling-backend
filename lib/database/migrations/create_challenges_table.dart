import 'package:vania/vania.dart';

class CreateChallengesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('challenges', () {
      uuid('id');
      primary('id');
      uuid('user_id');
      char('title', length: 200);
      string('description', length: 500);
      string('hashtags', length: 500, nullable: true);
      string('image_url', length: 500, nullable: true);
      json('media', nullable: true);
      string('thumbnail_url', length: 500, nullable: true);
      string('video_url', length: 500, nullable: true);
      string('media_kind', length: 20, defaultValue: 'image');
      string('storage_bucket', length: 100, nullable: true);
      string('storage_path', length: 500, nullable: true);
      string('mime_type', length: 120, nullable: true);
      integer('prize_bling', defaultValue: 0);
      integer('is_active', defaultValue: 1);
      timeStamp('ends_at', nullable: true);
      timeStamp('deleted_at', nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('challenges');
  }
}
