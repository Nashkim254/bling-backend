import 'package:vania/vania.dart';

class CreateChallengesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('challenges', () {
      char('id');
      primary('id');
      char("user_id");
      char("post_id");
      timeStamp("deleated_at", nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('challenges');
  }
}
