import 'package:vania/vania.dart';

class CreateRepostsTable extends Migration {

  @override
  Future<void> up() async{
   super.up();
   await createTableNotExists('reposts', () {
      id();
      timeStamps();
    });
  }
  
  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('reposts');
  }
}
