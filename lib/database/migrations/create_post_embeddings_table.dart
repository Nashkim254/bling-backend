import 'package:vania/vania.dart';

class CreatePostEmbeddingsTable extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement('CREATE EXTENSION IF NOT EXISTS vector', []);

    await connection!.statement(
      '''
      CREATE TABLE IF NOT EXISTS post_embeddings (
        post_id UUID PRIMARY KEY,
        user_id UUID NOT NULL,
        embedding VECTOR(256) NOT NULL,
        created_at TIMESTAMP NULL,
        updated_at TIMESTAMP NULL
      )
      ''',
      [],
    );

    await connection!.statement(
      '''
      CREATE INDEX IF NOT EXISTS post_embeddings_user_id_idx
      ON post_embeddings (user_id)
      ''',
      [],
    );

    await connection!.statement(
      '''
      CREATE INDEX IF NOT EXISTS post_embeddings_embedding_cosine_idx
      ON post_embeddings
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100)
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await dropIfExists('post_embeddings');
  }
}
