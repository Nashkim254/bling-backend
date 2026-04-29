# Bling Backend

Local development guide for the Dart/Vania API, including the PostgreSQL `pgvector` feed recommender.

## Local Services

### PostgreSQL

The backend reads database settings from [`.env`](/Users/value8/startup/blingSocial/bling/.env).

Current local defaults in this repo:

```env
DB_CONNECTION=postgresql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=vania_bling
DB_USERNAME=value8
DB_PASSWORD=root
```

Make sure that database exists before running migrations.

### PostgreSQL With `pgvector`

Use PostgreSQL with the `vector` extension available. The included Docker Compose file uses `pgvector/pgvector:pg16`, so local and droplet deployments do not need a separate vector database.

## Commands To Run

Run these from the backend directory:

```bash
cd /Users/value8/startup/blingSocial/bling
```

Install dependencies:

```bash
dart pub get
```

Run database migrations:

```bash
dart run lib/database/migrations/migrate.dart
```

Optional: seed local data:

```bash
dart run lib/database/seeds/seed.dart
```

Start the backend API:

```bash
dart run bin/server.dart
```

## Recommended Local Start Order

1. Start PostgreSQL.
2. Ensure PostgreSQL is running.
3. Run migrations.
4. Optionally seed sample data.
5. Start the backend server.

## Local URLs

- API: `http://127.0.0.1:8000`
- PostgreSQL: `127.0.0.1:5432`

## Notes

- The `vector` extension and `post_embeddings` table are created by the migration runner.
- Feed recommendations are stored and queried directly in PostgreSQL.
