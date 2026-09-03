# Dipstick — Architecture & Technical Notes

Companion doc to Dipstick_Spec.md. Read that first for feature intent; this covers
the full-stack architecture and the specific technologies to practice.

## 1. High-Level Architecture

```
[ iOS App (SwiftUI) ]
        |  HTTPS / JSON
        v
[ API Gateway / Load balancer (optional, or direct) ]
        |
   -----------------------------
   |                           |
[ vehicle-service (Go) ]   [ activity-service (Go) ]
   |                           |
   -----------------------------
                |
         [ Postgres DB ]
```

Two services instead of one monolith, so this is genuine (if slightly
over-engineered on purpose) microservice architecture practice:

- **vehicle-service**: owns Vehicle CRUD (name, make, model, year, VIN, odometer).
- **activity-service**: owns FuelEntry and MaintenanceEntry CRUD, MPG calculation,
  and due-date/maintenance-reminder logic. Calls vehicle-service (over HTTP) when it
  needs current vehicle data (e.g. current odometer), rather than sharing a database
  table directly — that inter-service call is the actual microservices lesson here.

Both services share one Postgres instance for v1 (separate *schemas*, not separate
databases, to keep local dev simple) — a natural place to later split into fully
separate databases per service if you want to go further.

## 2. Backend Language & Style

- **Go**, using the standard library `net/http` (Go 1.22+ has a solid built-in router
  now, no need for a third-party framework like Gin for a project this size — better
  for learning idiomatic Go than hiding behind a framework).
- Structure each service around: `main.go`, `handlers/`, `models/`, `store/` (DB access
  layer), `service/` (business logic — MPG calc, due-date calc).
- Use Go's `database/sql` with the `pgx` driver for Postgres access.

## 3. Database Schema (Postgres)

Each service owns its own Postgres **schema** (namespace) in the shared instance:
`vehicle` for vehicle-service, `activity` for activity-service. A service connects
with `search_path` pointed at its own schema and never reads or writes the other's
tables. The empty schemas are created by a one-time init script
(`backend/db/init/`); the tables inside them are created by each service's
own `golang-migrate` migrations.

```sql
-- schema: vehicle  (owned by vehicle-service)
CREATE TABLE vehicles (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    year INT,
    make TEXT,
    model TEXT,
    vin TEXT,
    current_odometer INT NOT NULL DEFAULT 0
);

-- schema: activity  (owned by activity-service)
CREATE TABLE fuel_entries (
    id SERIAL PRIMARY KEY,
    vehicle_id INT NOT NULL,       -- logical reference to vehicle.vehicles.id; NOT a DB foreign key
    date DATE NOT NULL,
    odometer INT NOT NULL,
    gallons NUMERIC(6,3) NOT NULL,
    total_cost NUMERIC(8,2) NOT NULL,
    is_full_tank BOOLEAN NOT NULL DEFAULT TRUE,
    station_name TEXT,
    notes TEXT
);

CREATE TABLE maintenance_entries (
    id SERIAL PRIMARY KEY,
    vehicle_id INT NOT NULL,       -- logical reference to vehicle.vehicles.id; NOT a DB foreign key
    date DATE NOT NULL,
    odometer INT NOT NULL,
    service_type TEXT NOT NULL,
    cost NUMERIC(8,2) NOT NULL DEFAULT 0,
    parts_used JSONB,              -- array of {name, cost} objects
    notes TEXT,
    next_due_odometer INT,
    next_due_date DATE
);
```

### 3.1 Why `vehicle_id` is not a foreign key

`fuel_entries.vehicle_id` and `maintenance_entries.vehicle_id` are plain `INT`
columns with **no `REFERENCES` constraint**. A real FK would force
activity-service's tables to depend on vehicle-service's table living in the same
database — exactly the coupling the two-service split is meant to avoid. Instead:

- activity-service treats `vehicle_id` as an opaque identifier it stores and
  echoes back.
- When it needs to confirm a vehicle exists, or read its current odometer, it
  calls **vehicle-service's HTTP API** (`GET /vehicles/{id}`), not the database.
- Consequences we accept: the DB will not stop you inserting a fuel entry for a
  non-existent vehicle (activity-service validates that itself via the API call),
  and deleting a vehicle does **not** cascade-delete its activity rows (handled at
  the application level in a later milestone — e.g. vehicle-service emits a
  delete event, or activity-service cleans up lazily).

This is the core microservices trade-off: we give up a database-enforced
invariant to gain independently deployable, independently ownable services.

## 4. Key Logic (implemented in activity-service, Go)

### MPG Calculation
- Only computed **between two consecutive full-tank fill-ups** for a given vehicle
  (ordered by odometer/date).
- `MPG = (currentFullTank.odometer - previousFullTank.odometer) / gallonsUsedSinceThen`
  where `gallonsUsedSinceThen` sums gallons from the current full-tank entry and any
  partial fill-ups logged since the previous full tank.
- **Data structures & algorithms angle**: implement this as a clean pass over a
  sorted slice of entries (don't just brute-force query the DB per pair) — a good spot
  to practice writing an efficient single-pass algorithm with a running window, and to
  write real unit tests around edge cases (first-ever entry, all-partial runs, etc).

### Maintenance "Due" Logic
- For each vehicle + distinct `service_type`, compare current odometer/date against
  the most recent entry's `next_due_odometer` / `next_due_date`.
- Flag "due soon" within a tunable buffer (e.g. 500 mi or 2 weeks) and "overdue" past it.
- Another reasonable DS&A touch: model services and their due-intervals as a small
  priority queue/heap keyed by "how soon is this due" so the dashboard's "what's next"
  view is a cheap peek rather than a full rescan — optional, but a nice interview-story
  detail if you want one.

## 5. Client (iOS)

- SwiftUI, MVVM.
- Networking via `URLSession` + `async/await`, calling the backend's REST API.
- No local persistence needed for v1 (no offline mode) — view models fetch from the
  API and hold state in memory for the session. (SwiftData could be reintroduced later
  as an offline cache if you want that; not required now.)

## 6. API Contract (v1 sketch)

```
vehicle-service:
  GET    /vehicles
  POST   /vehicles
  GET    /vehicles/{id}
  PUT    /vehicles/{id}
  DELETE /vehicles/{id}

activity-service:
  GET    /vehicles/{id}/fuel-entries
  POST   /vehicles/{id}/fuel-entries
  GET    /vehicles/{id}/maintenance-entries
  POST   /vehicles/{id}/maintenance-entries
  GET    /vehicles/{id}/stats            (MPG trend, totals)
  GET    /due                            (due/overdue across all vehicles)
```

## 7. Dev Tools & Practices (per JD)

- **Git**: feature-branch workflow (`feature/vehicle-crud`, etc.), PRs into `main`
  even though you're the only developer — good habit-building.
- **Bash/zsh**: a `scripts/` folder with small scripts (`run-local.sh` to spin up
  Docker Compose, `migrate.sh` to run DB migrations, `test.sh` to run the Go test
  suite) — real scripting reps, not just app code.
- **Docker**: a `Dockerfile` per Go service, plus a `docker-compose.yml` that runs
  both services + Postgres together for local dev.
- **CI/CD**: GitHub Actions workflow that on push to `main`:
  1. Runs `go test ./...` for both services.
  2. Builds Docker images.
  3. Pushes images to a registry (GitHub Container Registry is free and simple).
  4. Deploys to the hosting target (step below).
- **SDLC**: keep using this two-doc spec pattern per milestone — write/update the
  spec section, then implement, then check it off. Simple but it's the real shape of
  the lifecycle (requirements → design → build → test → deploy).

## 8. Deployment & Networking (per JD)

- **Hosting**: a low-cost option like Fly.io, Render, or a small DigitalOcean
  droplet — any of these support Docker deploys directly, so your CI/CD pipeline
  pushes straight to it.
- **Domain + DNS**: register a cheap domain (or use a free subdomain from the host)
  and point an A/CNAME record at the deployed service — real, hands-on DNS
  configuration, not simulated.
- **HTTPS**: use Let's Encrypt (most hosts automate this) so the iOS app talks to the
  API over TLS, not plain HTTP — also satisfies App Transport Security requirements
  on iOS by default.
- **Networking concepts this exercises naturally**: DNS resolution, TCP/TLS handshake,
  HTTP request/response cycle, status codes, and where your app's calls sit in the
  OSI model (app layer HTTP over transport-layer TCP) — worth being able to explain
  in an interview, not just implement.

## 9. Suggested Build Order (milestones for Claude Code sessions)

1. Postgres schema + migrations; vehicle-service with Vehicle CRUD; Docker Compose
   for local dev (Go service + Postgres only, no iOS yet).
2. activity-service: fuel entry CRUD + MPG calculation logic + unit tests.
3. activity-service: maintenance entry CRUD + due-date logic + unit tests.
4. Wire up inter-service call (activity-service → vehicle-service) for odometer reads.
5. iOS app: vehicle list/detail screens calling vehicle-service.
6. iOS app: fuel log + maintenance log screens calling activity-service.
7. GitHub Actions CI/CD pipeline (test → build → push images).
8. Deploy both services + Postgres to the chosen host; DNS + HTTPS; point the iOS
   app at the real deployed URL.
9. Polish: dashboard/due-soon view, stats/MPG chart.

Each milestone is a good unit for a single focused Claude Code session.
