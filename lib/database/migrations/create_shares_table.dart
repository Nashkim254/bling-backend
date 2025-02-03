import 'package:vania/vania.dart';

class CreateSharesTable extends Migration {

  @override
  Future<void> up() async{
   super.up();
   await createTableNotExists('shares', () {
      char('id');
      primary('id');
      timeStamps();
    });
  }
  
  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('shares');
  }
}
