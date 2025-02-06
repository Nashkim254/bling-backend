import 'package:vania/vania.dart';

class CreateChatsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('chats', () {
      id();
      char('from', length: 255);
      char('to', length: 255);
      string('content');
      char('timestamp');
      timeStamp('deleated_at', nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('chats');
  }
}
