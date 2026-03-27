import 'package:vania/vania.dart';

class CreateNotificationsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('notifications', () {
      uuid('id');
      primary('id');
      uuid('user_id'); // recipient
      char('type',
          length: 100); // 'like','comment','follow','bling_received', etc.
      char('title', length: 200);
      string('body', length: 500);
      json('data', nullable: true); // extra payload
      integer('is_read', defaultValue: 0);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('notifications');
  }
}
