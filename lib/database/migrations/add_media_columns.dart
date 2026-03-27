import 'package:vania/vania.dart';

class AddMediaColumns extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await _addColumns('posts', {
      'media': 'JSON',
      'thumbnail_url': 'TEXT',
      'video_url': 'TEXT',
      'media_kind': "VARCHAR(20) DEFAULT 'image'",
      'storage_bucket': 'TEXT',
      'storage_path': 'TEXT',
      'mime_type': 'TEXT',
    });

    await _addColumns('challenges', {
      'media': 'JSON',
      'thumbnail_url': 'TEXT',
      'video_url': 'TEXT',
      'media_kind': "VARCHAR(20) DEFAULT 'image'",
      'storage_bucket': 'TEXT',
      'storage_path': 'TEXT',
      'mime_type': 'TEXT',
    });

    await _addColumns('ads', {
      'thumbnail_url': 'TEXT',
      'video_url': 'TEXT',
      'media_kind': "VARCHAR(20) DEFAULT 'image'",
      'storage_bucket': 'TEXT',
      'storage_path': 'TEXT',
      'mime_type': 'TEXT',
    });
  }

  Future<void> _addColumns(String table, Map<String, String> columns) async {
    for (final entry in columns.entries) {
      await connection!.statement(
        'ALTER TABLE $table ADD COLUMN IF NOT EXISTS ${entry.key} ${entry.value}',
        [],
      );
    }
  }

  @override
  Future<void> down() async {
    super.down();
    await _dropColumns('posts');
    await _dropColumns('challenges');
    await _dropColumns('ads');
  }

  Future<void> _dropColumns(String table) async {
    for (final column in [
      'thumbnail_url',
      'video_url',
      'media_kind',
      'media',
      'storage_bucket',
      'storage_path',
      'mime_type',
    ]) {
      await connection!.statement(
        'ALTER TABLE $table DROP COLUMN IF EXISTS $column',
        [],
      );
    }
  }
}
