import 'package:vania/vania.dart';

class CreateChatsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('chats', () {
      uuid('id');
      primary('id');
      char('from_user_id', length: 255);
      char('to_user_id', length: 255);
      string('content');
      integer('is_read', defaultValue: 0);
      integer('delivered', defaultValue: 0);
      timeStamp('deleted_at', nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('chats');
  }
}
