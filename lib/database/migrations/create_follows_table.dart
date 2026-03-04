import 'package:vania/vania.dart';

class CreateFollowsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('follows', () {
      uuid('id');
      primary('id');
      uuid('follower_id');
      uuid('following_id');
      timeStamp('created_at', nullable: true);
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('follows');
  }
}
