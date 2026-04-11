# Bling Backend

Local development guide for the Dart/Vania API, including the Qdrant-based feed recommender.

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

### Qdrant

Native local Qdrant is already configured for this repo.

Config file:
[.qdrant-dev/config.yaml](/Users/value8/startup/blingSocial/.qdrant-dev/config.yaml)

Storage path:
`/Users/value8/startup/blingSocial/.qdrant-dev/storage`

Backend `.env` values already added:

```env
QDRANT_URL=http://127.0.0.1:6333
QDRANT_API_KEY=
QDRANT_POSTS_COLLECTION=feed_posts
QDRANT_VECTOR_SIZE=256
```

The backend will now read these values from `.env`, so you do not need to export Qdrant env vars manually for local development.

## Commands To Run

Run these from the backend directory:

```bash
cd /Users/value8/startup/blingSocial/bling
```

Install dependencies:

```bash
dart pub get
```

Start local Qdrant:

```bash
qdrant --config-path /Users/value8/startup/blingSocial/.qdrant-dev/config.yaml
```

Verify Qdrant is up:

```bash
curl http://127.0.0.1:6333
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
2. Start Qdrant.
3. Run migrations.
4. Optionally seed sample data.
5. Start the backend server.

## Local URLs

- API: `http://127.0.0.1:8000`
- Qdrant HTTP: `http://127.0.0.1:6333`
- Qdrant gRPC: `127.0.0.1:6334`

## Notes

- The feed recommendation collection is created automatically on first use.
- If Qdrant is not running, the feed endpoint falls back toward the SQL timeline path, but vector recommendations will not work.
- For local dev, `QDRANT_API_KEY` should stay empty unless you enable auth in your own Qdrant setup.
