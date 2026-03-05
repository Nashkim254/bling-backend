import 'package:vania/vania.dart';

class CreateConversationsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('conversations', () {
      uuid('id');
      primary('id');
      char('type', length: 10); // 'dm' | 'group'
      string('name', nullable: true);
      text('avatar', nullable: true);
      char('created_by', length: 255);
      text('last_message', nullable: true);
      char('last_message_sender_id', length: 255, nullable: true);
      timeStamp('last_message_at', nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('conversations');
  }
}
