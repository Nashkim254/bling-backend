import 'package:vania/vania.dart';

class CreateLikesTable extends Migration {

  @override
  Future<void> up() async{
   super.up();
   await createTableNotExists('likes', () {
      id();
      timeStamps();
    });
  }
  
  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('likes');
  }
}
