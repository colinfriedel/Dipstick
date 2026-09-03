#!/usr/bin/env bash
#
# Run the Go test suite for every backend service. This is what CI will call in a
# later milestone, so keeping it as a script means "how we run tests" lives in
# one place.
#
# Usage:
#   ./scripts/test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Each service is its own Go module, so `go test` has to run inside each one.
# As more services are added, list their directories here.
SERVICES=(
  "backend/vehicle-service"
  "backend/activity-service"
)

for service in "${SERVICES[@]}"; do
  echo "==> testing $service"
  ( cd "$REPO_ROOT/$service" && go test ./... )
done
