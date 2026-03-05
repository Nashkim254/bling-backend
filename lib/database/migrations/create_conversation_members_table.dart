import 'package:vania/vania.dart';

class CreateConversationMembersTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('conversation_members', () {
      uuid('id');
      primary('id');
      char('conversation_id', length: 255);
      char('user_id', length: 255);
      char('role', length: 20, defaultValue: 'member'); // 'admin' | 'member'
      integer('is_pinned', defaultValue: 0);
      integer('is_archived', defaultValue: 0);
      timeStamp('last_read_at', nullable: true);
      timeStamp('joined_at');
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('conversation_members');
  }
}
