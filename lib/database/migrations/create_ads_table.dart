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
