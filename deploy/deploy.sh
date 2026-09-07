#!/usr/bin/env bash
#
# Deploy / update the running stack on the server. Idempotent — safe to re-run.
# Run from anywhere; it operates on this file's directory.
#
# CI calls this over SSH after new images are pushed. You can also run it by hand
# on the server after `git pull`.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -f .env ]]; then
  echo "deploy/.env not found — copy .env.example and fill it in" >&2
  exit 1
fi

COMPOSE=(docker compose -f docker-compose.prod.yml)

echo "==> Pulling images"
"${COMPOSE[@]}" pull --quiet postgres vehicle-migrate activity-migrate caddy
"${COMPOSE[@]}" pull vehicle-service activity-service

echo "==> Applying migrations"
# The migrate services run to completion and exit; --exit-code-from surfaces a
# failed migration as a non-zero exit here.
"${COMPOSE[@]}" run --rm vehicle-migrate
"${COMPOSE[@]}" run --rm activity-migrate

echo "==> Restarting services"
"${COMPOSE[@]}" up -d --remove-orphans

echo "==> Pruning old images"
docker image prune -f >/dev/null || true

echo "==> Current state"
"${COMPOSE[@]}" ps
