#!/usr/bin/env bash
#
# Run the same checks CI runs, for every backend service: formatting, vet, lint,
# and the test suite. Use this before pushing.
#
# Needs golangci-lint on PATH (brew install golangci-lint).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERVICES=(
  "backend/vehicle-service"
  "backend/activity-service"
)

for service in "${SERVICES[@]}"; do
  echo "==> $service"
  cd "$REPO_ROOT/$service"

  unformatted="$(gofmt -l .)"
  if [[ -n "$unformatted" ]]; then
    echo "  gofmt needed:" >&2
    echo "$unformatted" >&2
    exit 1
  fi
  echo "  gofmt   ok"

  go vet ./...
  echo "  vet     ok"

  if command -v golangci-lint >/dev/null 2>&1; then
    golangci-lint run ./...
    echo "  lint    ok"
  else
    echo "  lint    skipped (golangci-lint not installed)"
  fi

  go test -race ./...
  echo "  test    ok"
done

echo "all checks passed"
