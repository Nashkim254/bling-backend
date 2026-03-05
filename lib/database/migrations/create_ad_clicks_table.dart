import 'package:vania/vania.dart';

class CreateAdClicksTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('ad_clicks', () {
      uuid('id');
      primary('id');
      char('ad_id', length: 255);
      char('user_id', length: 255);
      timeStamp('created_at', nullable: true);
    });
    await connection!.statement(
      'CREATE INDEX IF NOT EXISTS idx_ad_clicks_ad ON ad_clicks (ad_id)',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('ad_clicks');
  }
}
