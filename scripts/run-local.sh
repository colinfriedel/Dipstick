#!/usr/bin/env bash
#
# Spin up the full local backend stack (Postgres + migrations + vehicle-service)
# via Docker Compose, rebuilding images that changed.
#
# Usage:
#   ./scripts/run-local.sh            # start in the foreground, Ctrl-C to stop
#   ./scripts/run-local.sh -d         # start detached (background)
#   ./scripts/run-local.sh down       # stop and remove containers
#   ./scripts/run-local.sh nuke       # stop and also delete the database volume

set -euo pipefail

# Always operate from the repo root, regardless of where the script is called from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

case "${1:-up}" in
  down)
    docker compose down
    ;;
  nuke)
    docker compose down --volumes
    ;;
  -d)
    docker compose up --build -d
    ;;
  up)
    docker compose up --build
    ;;
  *)
    echo "unknown argument: $1" >&2
    echo "usage: $0 [up | -d | down | nuke]" >&2
    exit 1
    ;;
esac
