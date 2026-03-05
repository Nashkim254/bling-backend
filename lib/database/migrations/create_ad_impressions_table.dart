import 'package:vania/vania.dart';

class CreateAdImpressionsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await createTableNotExists('ad_impressions', () {
      uuid('id');
      primary('id');
      char('ad_id', length: 255);
      char('user_id', length: 255);
      timeStamp('created_at', nullable: true);
    });
    // Frequency cap: one impression per user per ad per day (checked in query)
    await connection!.statement(
      'CREATE INDEX IF NOT EXISTS idx_ad_impressions_ad_user ON ad_impressions (ad_id, user_id)',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('ad_impressions');
  }
}
