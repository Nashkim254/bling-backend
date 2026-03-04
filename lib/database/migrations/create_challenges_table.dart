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
