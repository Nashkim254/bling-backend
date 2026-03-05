import 'package:vania/vania.dart';

/// Upgrades the ads table from a simple content table to a full campaign system.
class AddAdCampaignColumns extends Migration {
  @override
  Future<void> up() async {
    super.up();
    final cols = {
      'advertiser_id': "VARCHAR(255)",           // user who owns the campaign
      'budget_bling': "INTEGER DEFAULT 500",      // total bling allocated
      'spent_bling': "INTEGER DEFAULT 0",         // running debit
      'cpm_bling': "INTEGER DEFAULT 50",          // bling per 1,000 impressions
      'total_impressions': "INTEGER DEFAULT 0",   // cached counter
      'total_clicks': "INTEGER DEFAULT 0",        // cached counter
      'target_min_level': "INTEGER",              // nullable — no level filter
      'target_verified_only': "BOOLEAN DEFAULT false",
      'start_at': "TIMESTAMP",
      'end_at': "TIMESTAMP",
      'status': "VARCHAR(20) DEFAULT 'active'",   // draft|active|paused|exhausted
    };

    for (final entry in cols.entries) {
      await connection!.statement(
        'ALTER TABLE ads ADD COLUMN IF NOT EXISTS ${entry.key} ${entry.value}',
        [],
      );
    }

    // Index for fast serving query
    await connection!.statement(
      "CREATE INDEX IF NOT EXISTS idx_ads_status_advertiser ON ads (status, advertiser_id)",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    for (final col in [
      'advertiser_id', 'budget_bling', 'spent_bling', 'cpm_bling',
      'total_impressions', 'total_clicks', 'target_min_level',
      'target_verified_only', 'start_at', 'end_at', 'status',
    ]) {
      await connection!.statement(
        'ALTER TABLE ads DROP COLUMN IF EXISTS $col',
        [],
      );
    }
  }
}
