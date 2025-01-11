import 'package:vania/vania.dart';

class CreateUserTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('users', () {
      id();
      char('name', length: 100);
      char('username', length: 100);
      char('email', length: 100);
      char('msisdn', length: 20);
      char('password', length: 255);
      char('avatar', length: 50);
      char('account_type', length: 50, defaultValue: 'public');
      char('bio', length: 255);
      timeStamps();
      timeStamp('deleted_at', nullable: true);
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('users');
  }
}
