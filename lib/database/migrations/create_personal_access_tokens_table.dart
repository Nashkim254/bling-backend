import 'package:vania/vania.dart';

class CreatePersonalAccessTokensTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('personal_access_tokens', () {
      id();
      char('name', length: 255);
      bigInt('tokenable_id');
      char('token', length: 64, unique: true);
      timeStamp('deleated_at', nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('personal_access_tokens');
  }
}
