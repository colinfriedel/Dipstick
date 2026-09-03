#!/usr/bin/env bash
#
# Run golang-migrate against the local Postgres for a single service, using the
# dockerized migrate CLI so nothing needs to be installed on your machine.
#
# Postgres must already be running (./scripts/run-local.sh -d, or just the db:
# `docker compose up -d postgres`).
#
# Usage (service is "vehicle" or "activity"):
#   ./scripts/migrate.sh vehicle  up             # apply all pending migrations
#   ./scripts/migrate.sh activity up
#   ./scripts/migrate.sh vehicle  down 1         # roll back the last migration
#   ./scripts/migrate.sh vehicle  version        # print current version
#   ./scripts/migrate.sh vehicle  force 1        # reset a "dirty" state to v1
#   ./scripts/migrate.sh activity create add_foo # scaffold a new migration pair

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <service> <migrate-command> [args...]" >&2
  echo "  service: vehicle | activity" >&2
  exit 1
fi

SERVICE="$1"
shift

MIGRATIONS_DIR="$REPO_ROOT/backend/${SERVICE}-service/migrations"
if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "no migrations directory for service '$SERVICE' (looked in $MIGRATIONS_DIR)" >&2
  exit 1
fi

# Each service confines itself to its own schema; search_path keeps
# golang-migrate's bookkeeping table there too.
SCHEMA="$SERVICE"
DB_URL="postgres://dipstick:dipstick@postgres:5432/dipstick?sslmode=disable&search_path=${SCHEMA}"

# `create` just writes files into the mounted directory; it needs no database.
if [[ "$1" == "create" ]]; then
  shift
  NAME="${1:?migration name required, e.g. add_indexes}"
  docker run --rm -v "$MIGRATIONS_DIR:/migrations" migrate/migrate:v4.18.1 \
    create -ext sql -dir /migrations -seq "$NAME"
  exit 0
fi

# Everything else talks to Postgres, so join its Compose network.
docker run --rm \
  --network dipstick_default \
  -v "$MIGRATIONS_DIR:/migrations" \
  migrate/migrate:v4.18.1 \
  -path /migrations -database "$DB_URL" "$@"
