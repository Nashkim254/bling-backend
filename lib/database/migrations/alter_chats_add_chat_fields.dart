import 'package:vania/vania.dart';

/// Extends the chats (messages) table with fields for:
/// - conversation_id: ties messages to a conversation
/// - reply_to_id: thread reply support
/// - message_type: text / image / file
/// - file_url / file_name / file_size: file attachments
/// - is_deleted / edited_at: edit & soft-delete support
class AlterChatsAddChatFields extends Migration {
  @override
  Future<void> up() async {
    super.up();
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS conversation_id VARCHAR(255)",
      [],
    );
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS reply_to_id VARCHAR(255)",
      [],
    );
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text'",
      [],
    );
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS file_url TEXT",
      [],
    );
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS file_name VARCHAR(255)",
      [],
    );
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS file_size INTEGER DEFAULT 0",
      [],
    );
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS is_deleted INTEGER DEFAULT 0",
      [],
    );
    await connection!.statement(
      "ALTER TABLE chats ADD COLUMN IF NOT EXISTS edited_at TIMESTAMP",
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
  }
}
