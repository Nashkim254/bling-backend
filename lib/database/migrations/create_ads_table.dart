import 'package:vania/vania.dart';

class CreateAdsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('ads', () {
      uuid('id');
      primary('id');
      char('title', length: 200);
      string('body', length: 500);
      string('image_url', length: 500);
      string('thumbnail_url', length: 500, nullable: true);
      string('video_url', length: 500, nullable: true);
      string('media_kind', length: 20, defaultValue: 'image');
      string('storage_bucket', length: 100, nullable: true);
      string('storage_path', length: 500, nullable: true);
      string('mime_type', length: 120, nullable: true);
      string('target_url', length: 500, nullable: true);
      integer('is_active', defaultValue: 1);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('ads');
  }
}
