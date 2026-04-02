import 'package:vania/vania.dart';

class CreateGroupMembersTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('group_members', () {
      uuid('id');
      primary('id');
      char('group_id', length: 255);
      char('user_id', length: 255);
      char('role', length: 20, defaultValue: 'member');
      char('status', length: 20, defaultValue: 'active');
      timeStamp('joined_at');
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('group_members');
  }
}
