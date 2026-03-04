import 'package:vania/vania.dart';

class CreateBlingPackagesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('bling_packages', () {
      uuid('id');
      primary('id');
      char('name', length: 100);
      integer('bling_amount');
      integer('price_cents'); // price in USD cents (e.g. 99 = $0.99)
      integer('is_active', defaultValue: 1);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('bling_packages');
  }
}
