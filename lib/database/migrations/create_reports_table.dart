import 'package:vania/vania.dart';

class CreateReportsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('reports', () {
      uuid('id');
      primary('id');
      char('reporter_id', length: 100, nullable: false);
      // 'user' or 'post'
      char('reported_type', length: 20, nullable: false);
      char('reported_id', length: 100, nullable: false);
      string('reason', length: 500, nullable: true);
      // 'pending', 'reviewed', 'dismissed'
      char('status', length: 20, defaultValue: 'pending');
      timeStamps();
    });
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('reports');
  }
}
