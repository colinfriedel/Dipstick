-- Runs once, automatically, the first time the Postgres container initializes a
-- fresh data directory. The official postgres image executes every *.sql and
-- *.sh file mounted into /docker-entrypoint-initdb.d, in filename order.
--
-- We only create the empty schemas here. Everything inside them (tables,
-- indexes) is owned by each service's golang-migrate migrations. The split:
--   - "which namespaces exist"  -> infrastructure, here
--   - "what's in each namespace" -> versioned application migrations
--
-- Why schemas at all: docs/Dipstick_Architecture.md says the two services share
-- one Postgres instance but stay logically separate. Each service connects with
-- search_path pointed at its own schema, so it can't accidentally read or write
-- the other service's tables.
--
-- NOTE: if you change this file, it will NOT re-run on an existing volume. Run
-- `docker compose down -v` to wipe the volume, or create the schema by hand.

CREATE SCHEMA IF NOT EXISTS vehicle;
CREATE SCHEMA IF NOT EXISTS activity;
