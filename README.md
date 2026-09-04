# Dipstick

Personal full-stack app for tracking vehicle maintenance and fuel fill-ups — an
iOS/SwiftUI client talking to a Go backend.

[![Backend](https://github.com/colinfriedel/Dipstick/actions/workflows/backend.yml/badge.svg)](https://github.com/colinfriedel/Dipstick/actions/workflows/backend.yml)
[![iOS](https://github.com/colinfriedel/Dipstick/actions/workflows/ios.yml/badge.svg)](https://github.com/colinfriedel/Dipstick/actions/workflows/ios.yml)

See [`docs/Dipstick_Spec.md`](docs/Dipstick_Spec.md) for the product spec and
[`docs/Dipstick_Architecture.md`](docs/Dipstick_Architecture.md) for the
architecture. Per-milestone build notes are in [`docs/reports/`](docs/reports).

## Shape

```
iOS app (SwiftUI, MVVM)
      │  HTTPS / JSON
      ▼
vehicle-service (Go)  ◀── HTTP ──  activity-service (Go)
      │                                  │
      └──────────────┬───────────────────┘
                     ▼
                 Postgres
```

- **vehicle-service** (`:8081`) — Vehicle CRUD. Schema `vehicle`.
- **activity-service** (`:8082`) — fuel entries, maintenance entries, MPG, the
  "what's due" calc. Schema `activity`. Calls vehicle-service over HTTP; no
  shared tables.
- Both: Go standard-library `net/http`, `database/sql` + pgx, golang-migrate.

## Local development

Requires Docker and (for the backend) Go 1.22+, (for the app) Xcode.

```bash
./scripts/run-local.sh -d          # Postgres + both services via docker compose
curl localhost:8081/vehicles
curl localhost:8082/due
./scripts/run-local.sh nuke        # stop and wipe the database

./scripts/check.sh                 # what CI runs: fmt, vet, lint, test
./scripts/migrate.sh vehicle up    # run migrations for one service
```

The iOS app: `open ios/Dipstick/Dipstick.xcodeproj` and run on a simulator. To
run it on a device, use the app's **Settings › Server** to point it at your Mac
(`http://<your-mac>.local:8081` / `:8082`).

## CI

- **backend.yml** — on every PR and push to `main`: `gofmt`, `go vet`,
  `golangci-lint`, `go test -race` for both services. On push to `main` it also
  builds and pushes images to `ghcr.io/colinfriedel/dipstick-{vehicle,activity}-service`.
- **ios.yml** — on iOS changes: `xcodebuild build-for-testing` on a macOS runner
  (compiles the app + both test bundles). Running the tests in CI needs a
  downloaded simulator runtime — a later refinement; they run locally and in
  `scripts/check.sh`-adjacent workflows.

Deployment (DNS, HTTPS, a running host) is a later milestone.
