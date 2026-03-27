import 'package:vania/vania.dart';

class CreateBlingTransactionsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('bling_transactions', () {
      uuid('id');
      primary('id');
      uuid('user_id'); // initiator (buyer/sender)
      char('to_user_id', length: 255, nullable: true); // recipient (transfers)
      char('type',
          length: 50); // 'purchase','transfer_out','transfer_in','reward'
      integer('amount'); // bling amount
      char('reference', length: 200, nullable: true); // payment reference
      string('description', length: 500, nullable: true);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('bling_transactions');
  }
}
