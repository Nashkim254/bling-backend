import 'package:vania/vania.dart';

class CreateCommentsTable extends Migration {

  @override
  Future<void> up() async{
   super.up();
   await createTableNotExists('comments', () {
      id();
      timeStamps();
    });
  }
  
  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('comments');
  }
}
