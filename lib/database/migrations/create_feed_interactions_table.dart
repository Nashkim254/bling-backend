import 'package:vania/vania.dart';

class CreateFeedInteractionsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS feed_interactions (
        id CHAR(36) PRIMARY KEY,
        user_id CHAR(36) NOT NULL,
        post_id CHAR(36) NOT NULL,
        interaction_type VARCHAR(40) NOT NULL,
        source VARCHAR(40) NOT NULL DEFAULT 'feed',
        dwell_ms INTEGER NOT NULL DEFAULT 0,
        metadata TEXT NOT NULL DEFAULT '{}',
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
      ''',
      [],
    );
    await connection!.statement(
      'CREATE INDEX IF NOT EXISTS idx_feed_interactions_user_created ON feed_interactions (user_id, created_at DESC)',
      [],
    );
    await connection!.statement(
      'CREATE INDEX IF NOT EXISTS idx_feed_interactions_post_created ON feed_interactions (post_id, created_at DESC)',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement('DROP TABLE IF EXISTS feed_interactions', []);
  }
}
