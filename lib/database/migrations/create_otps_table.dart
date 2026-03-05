import 'package:vania/vania.dart';

class CreateOtpsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('otps', () {
      uuid('id');
      primary('id');
      char('email', length: 100);
      char('code', length: 10);
      timeStamp('expires_at');
      timeStamp('created_at', nullable: true);
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('otps');
  }
}
