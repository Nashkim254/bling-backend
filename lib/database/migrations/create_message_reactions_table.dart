import 'package:vania/vania.dart';

class CreateMessageReactionsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('message_reactions', () {
      uuid('id');
      primary('id');
      char('message_id', length: 255);
      char('user_id', length: 255);
      char('user_name', length: 255, nullable: true);
      char('emoji', length: 20);
      timeStamp('created_at');
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('message_reactions');
  }
}
