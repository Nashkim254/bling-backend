import 'package:vania/vania.dart';

class CreateSessionsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('sessions', () {
      id();
      char("user_id");
      char("status");
      char("type");
      char("token",length: 255);
      timeStamp('expires_at');
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('sessions');
  }
}
