import 'package:vania/vania.dart';

class CreateChallengesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('challenges', () {
      uuid('id');
      primary('id');
      uuid("user_id");
      uuid("post_id");
      timeStamp("deleted_at", nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('challenges');
  }
}
