import 'package:vania/vania.dart';

class CreateUserTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('users', () {
      uuid('id');
      primary('id');
      char('name', length: 100);
      char('username', length: 100, unique: true, nullable: false);
      char('email', length: 100, unique: true, nullable: false);
      char('msisdn', length: 20, nullable: true);
      string('password', length: 200);
      string('avatar', length: 500, nullable: true);
      string('cover_image', length: 500, nullable: true);
      char('account_type', length: 50, defaultValue: 'public');
      string('bio', length: 500, nullable: true);
      integer('bling_score', defaultValue: 0);
      integer('is_verified', defaultValue: 0);
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
