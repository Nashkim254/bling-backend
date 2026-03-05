import 'package:vania/vania.dart';

class CreateBlocksTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('blocks', () {
      uuid('id');
      primary('id');
      char('user_id', length: 100, nullable: false);
      char('blocked_user_id', length: 100, nullable: false);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('blocks');
  }
}
