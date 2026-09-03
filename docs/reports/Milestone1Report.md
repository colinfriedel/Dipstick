# Dipstick — Milestone 1 Report: vehicle-service

**Status:** Built and verified end-to-end. Compose stack comes up, migrations apply,
all six endpoints behave correctly against a real Postgres instance.

---

## Concepts Introduced This Milestone

**Go modules (`go.mod`)**
A module is a versioned collection of Go packages with its own dependency list. Each
service got its own module so they can evolve dependencies independently — the way
real, separately-deployed services do. `go mod tidy` resolves the dependency graph and
writes `go.sum` (cryptographic checksums of every dependency, so builds are
reproducible and tamper-evident).

**`database/sql` + a driver**
Go's standard library defines a generic database interface (`database/sql`) but ships
no database-specific code. A driver implements the actual wire protocol — here, `pgx`
for Postgres. It's imported for its side effect (its `init()` registers itself under
the name `"pgx"`), then `sql.Open("pgx", …)` returns a connection **pool** — not a
single connection, but a managed, reusable set safe for concurrent use.

**`net/http` routing (Go 1.22+)**
The standard `ServeMux` now understands method + path patterns like
`"GET /vehicles/{id}"` and exposes path segments via `r.PathValue("id")`. For basic
CRUD, this removes any real need for a third-party router like Gin or Chi. Middleware
is just a function that wraps a handler and calls through — that's how request logging
gets added without touching every individual handler.

**Migrations**
Instead of hand-editing the live database, every schema change is a numbered pair of
files (`…up.sql` / `…down.sql`). `golang-migrate` tracks which have run in a
`schema_migrations` table, so any environment can be brought to the same version, and
a bad change can be rolled back.

**Docker multi-stage build**
Stage 1 has the full (~1 GB) Go toolchain and compiles a static binary. Stage 2 starts
from a near-empty base image and copies in just that binary. The shipped image has no
compiler, shell, or package manager — smaller, and far less attack surface.

**Docker Compose networking**
Compose puts every container on one private network and makes each reachable by its
service name as a hostname — that's why connection strings use `@postgres:5432`:
inside the network, `postgres` resolves to the DB container. Your Mac only sees what's
explicitly published via `ports:`.

---

## File Reference

| File | Role |
|---|---|
| `backend/vehicle-service/go.mod` | Declares the module path and its one direct dependency (`pgx`). |
| `main.go` | Composition root: reads config from env vars, builds the store + router, waits for Postgres, serves HTTP, shuts down gracefully on `SIGTERM` (what `docker stop` sends). |
| `models/vehicle.go` | The `Vehicle` data type (mirrors a DB row) and `VehicleInput` (the client-writable subset). Nullable columns are `*int`/`*string` so "absent" is distinct from zero. |
| `store/store.go` | Opens and configures the connection pool; pins `search_path` to the `vehicle` schema so this service can't touch activity-service's tables. Exposes `ErrNotFound`. |
| `store/vehicle_store.go` | Every SQL statement the service runs — list/get/create/update/delete — using parameterized queries (`$1`, `$2`) and Postgres `RETURNING` to avoid follow-up `SELECT`s. |
| `handlers/respond.go` | JSON response helpers; one consistent `{"error": "..."}` shape for all failures. |
| `handlers/router.go` | Maps routes to handlers, adds logging middleware, exposes `GET /healthz`. |
| `handlers/vehicle_handlers.go` | Translates HTTP ↔ store calls: parses IDs, decodes + validates bodies, maps `ErrNotFound` → 404, everything else → 500. Defines the `VehicleStore` interface it depends on. |
| `handlers/vehicle_handlers_test.go` | Table of handler tests using an in-memory fake store — no database needed. |
| `migrations/000001_create_vehicles.{up,down}.sql` | Creates / drops the `vehicles` table. |
| `backend/db/init/00-create-schemas.sql` | Runs once on a fresh DB; creates the empty `vehicle` and `activity` schemas. |
| `Dockerfile` / `.dockerignore` | Multi-stage build → distroless final image. |
| `docker-compose.yml` | Orchestrates Postgres → migrate (one-shot) → vehicle-service, in dependency order. |
| `scripts/run-local.sh` | `up` / `-d` / `down` / `nuke` wrappers around Compose. |
| `scripts/migrate.sh` | Runs any `golang-migrate` command (`up`, `down N`, `version`, `force`, `create`) via the dockerized CLI. |
| `scripts/test.sh` | Runs `go test ./...` for every service — what CI will call later. |

---

## Design Decisions Made Beyond the Spec

- **Consumer-defined `VehicleStore` interface**, declared in the `handlers` package
  rather than `store`. This is idiomatic Go: the code that *needs* a dependency
  declares the minimal interface it uses, and the concrete `*store.Store` satisfies it
  implicitly. This is what makes handler tests possible without a real database.
- **`GET /healthz` does not check the database.** It answers "is the process alive"
  (for Compose/deploy platforms), not "is everything healthy." A DB-checking
  readiness endpoint can be added later if deployment needs one.
- **`DisallowUnknownFields()`** on the JSON decoder — a misspelled field (e.g.
  `"colour"`) is rejected with a 400 rather than silently ignored. Stricter, catches
  typos early.
- **Status codes**: `201` create, `204` delete, `400` malformed input (bad JSON/bad
  ID), `422` well-formed input that breaks a rule (e.g. missing name), `404` unknown ID.

---

## Verification (Actually Run)

```
POST /vehicles {"name":"Daily Driver",...}   → 201 {"id":1,...}
POST /vehicles {"name":"Project Car"}        → 201 {"id":2,"year":null,...}
GET  /vehicles                               → [both]
GET  /vehicles/999                           → 404 {"error":"vehicle not found"}
POST /vehicles {                             → 400 {"error":"invalid JSON body: unexpected EOF"}
POST /vehicles {"year":2020}                 → 422 {"error":"name is required"}
PUT  /vehicles/2 {...}                       → 200 (updated)
DELETE /vehicles/1                           → 204
```

Confirmed directly in Postgres: `schema_migrations` and `vehicles` both landed in the
`vehicle` schema; the `activity` schema exists and is empty. `go test ./...` and
`./scripts/test.sh` all pass. The stack was torn down with `down -v` afterward, so the
next run starts from a clean database.

---

## How to Run It Yourself

Go and Docker aren't yet on your shell's PATH (they're installed at
`/opt/homebrew/bin` and `~/.docker/bin`) — add both to your `~/.zshrc`, then:

```bash
cd ~/Documents/Projects/Dipstick
./scripts/run-local.sh -d          # build + start in background
curl -s localhost:8081/vehicles    # → []
docker compose logs -f vehicle-service
./scripts/run-local.sh nuke        # stop + wipe the DB volume
```

- API: `localhost:8081`
- Postgres: `localhost:5432` (user/pass/db: `dipstick`/`dipstick`/`dipstick`)

---

## Post-Report Updates

Both open items below were resolved in the same session, after this report was
first written:

- **`vehicle_id` contradiction — RESOLVED (go with the architecture doc).**
  `fuel_entries` / `maintenance_entries` will use a plain `vehicle_id INT NOT NULL`
  with **no `REFERENCES` constraint**. `activity-service` will validate vehicles and
  read odometer via `vehicle-service`'s HTTP API, never by querying the `vehicles`
  table. `Dipstick_Architecture.md` §3 was updated and a new §3.1 documents the
  trade-off. No migration change was needed (the fuel/maintenance tables don't exist
  until Milestone 2). See "Open Items for Milestone 2" below for the unreachable-
  upstream handling plan.
- **Git — DONE.** Committed on a `feature/vehicle-crud` branch (off `main`), split
  into three commits: the spec note, the architecture decoupling doc change, and the
  `feat(vehicle-service)` implementation. Pushed to `origin`; PR opened into `main`.

---

## Open Items for Milestone 2

**Building `activity-service`: fuel entry CRUD + MPG calculation.** Key design point
carried forward — how `activity-service` handles `vehicle-service` being unreachable
when creating a fuel/maintenance entry (it must call `GET /vehicles/{id}` to validate
the vehicle and read its odometer):

- **Dedicated `http.Client` with a timeout** (not `http.DefaultClient`, which never
  times out) plus a per-request `context`.
- **Distinguish "not found" from "outage":** upstream `404` → `422` to the caller
  (real validation failure); timeout / connection refused / `5xx` → `503` +
  `Retry-After`, and **the entry is not written**.
- **Fail closed on writes.** With no FK, a bad `vehicle_id` silently corrupts MPG and
  due-date math forever. Rejecting a valid create is cheap (client retries); accepting
  an invalid one is a data bug.
- **Degrade reads, don't fail them.** `/stats` and `/due` run mostly off data
  `activity-service` already owns; if the live odometer is unavailable, serve the
  computed result off the last-known odometer and flag it stale in the response.
- **One short retry + a ~30–60s in-memory cache** of `GET /vehicles/{id}` to absorb
  bursts and brief blips. Cache is a fallback, not the source of truth.
- **Out of scope for v1:** circuit breakers, sagas/distributed transactions.
  Orphaned-row cleanup on vehicle delete is handled in Milestone 4.

> Note: a few lines in the original Claude Code output were cut off mid-sentence when
> copied over (table wrapping / truncation). The reconstructions above are based on
> context and are very likely accurate, but worth a quick sanity check against the
> actual terminal output if anything here looks off.
