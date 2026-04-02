import 'package:vania/vania.dart';

class CreateGroupsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('groups', () {
      uuid('id');
      primary('id');
      string('name');
      text('description', nullable: true);
      text('avatar', nullable: true);
      text('cover_image', nullable: true);
      integer('required_level', defaultValue: 0);
      integer('medals_count', defaultValue: 0);
      char('visibility', length: 20, defaultValue: 'public');
      integer('is_active', defaultValue: 1);
      char('created_by', length: 255);
      char('conversation_id', length: 255, nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('groups');
  }
}
