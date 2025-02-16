import 'package:vania/vania.dart';

class CreateUserTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('users', () {
      char('id');
      primary('id');
      char('name', length: 100);
      char('username', length: 100, unique: true, nullable: false);
      char('email', length: 100, unique: true, nullable: false);
      char('msisdn', length: 20);
      string('password', length: 200);
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
