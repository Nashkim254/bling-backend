import 'package:vania/vania.dart';

class CreateChallengeEntriesTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('challenge_entries', () {
      uuid('id');
      primary('id');
      uuid('challenge_id');
      uuid('user_id');
      uuid('post_id', nullable: true); // post created for this entry
      integer('is_winner', defaultValue: 0);
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('challenge_entries');
  }
}
