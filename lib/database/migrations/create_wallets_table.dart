import 'package:vania/vania.dart';

class CreateWalletsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('wallets', () {
      uuid('id');
      primary('id');
      uuid('user_id', unique: true);
      integer('balance', defaultValue: 0);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('wallets');
  }
}
