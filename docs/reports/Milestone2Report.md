# Dipstick — Milestone 2 Report: activity-service (fuel log + MPG)

**Status:** Built and verified end-to-end. Both services run under Compose,
migrations apply into their own schemas, fuel entries are created and listed,
MPG is computed correctly, and the vehicle-service-unreachable path returns a
`503` without writing anything.

---

## Concepts Introduced This Milestone

**A second Go module with duplicated plumbing**
`activity-service` is its own module (`go.mod`) with its own `store/store.go`,
`handlers/respond.go`, and `main.go` lifecycle code that are near-copies of
vehicle-service's. That duplication is the deliberate cost of "two independently
deployable services." If it becomes painful, the shared pieces can move into a
third module later — but not before it actually hurts.

**Custom types that cross both boundaries (`sql.Scanner` / `driver.Valuer` / `json.Marshaler`)**
`models.Date` represents the Postgres `DATE` column as a plain calendar day. It
implements four interfaces so the same value moves cleanly in and out of JSON
(`MarshalJSON` / `UnmarshalJSON`) and the database (`Value` / `Scan`). This keeps
a value that means "2024-03-14" from secretly carrying a midnight timestamp and a
timezone that could shift it a day. This 4-interface pattern recurs constantly in
Go for money, enums, coordinates, etc.

**An outbound HTTP client (the inter-service call)**
`client/vehicle_client.go` calls vehicle-service's REST API. Key pieces:
- Its own `*http.Client` with `Timeout: 3s` — `http.DefaultClient` has *no*
  timeout and a hung upstream would pin a goroutine forever.
- `http.NewRequestWithContext` so the caller's request cancellation propagates.
- A bounded retry: one extra attempt on a transient failure (network error / 5xx)
  with a 200ms backoff; a `404` is definitive and never retried.
- Sentinel errors (`ErrVehicleNotFound`, `ErrVehicleServiceUnavailable`) so the
  handler can turn "no such vehicle" into `422` and "can't reach the service"
  into `503`.

**Single-pass algorithm over a sorted slice (MPG)**
`service.CalculateMPG` sorts the entries by odometer once, then walks them once
carrying a running "gallons since the last full tank" accumulator. `O(n log n)`
for the sort, `O(n)` for the walk — no per-pair database queries, no nested
loops. It works on a *copy* so the caller's display-ordered slice is untouched.

**Table-driven tests**
`service/mpg_test.go` is one test function with a slice of `{name, input,
expected}` cases — Go's standard way to cover many scenarios compactly. Cases
include: no entries, single full tank, full→full, full→partial→full, all-partial,
partials-before-first-full-tank, three full tanks, unsorted input, zero-mile
interval, trailing partial, and zero-gallon closing tank.

---

## File Reference

| File | Role |
|---|---|
| `backend/activity-service/go.mod` | Module definition; one direct dep (`pgx`). |
| `models/date.go` | The `Date` calendar type + its 4 interface implementations. |
| `models/fuel.go` | `FuelEntry` (row + derived `CostPerGallon`/`MPG`) and `FuelEntryInput` (request body). |
| `service/mpg.go` | `CalculateMPG` — the single-pass full-tank-interval algorithm. Pure function, no I/O. |
| `service/enrich.go` | `EnrichFuelEntries` — fills `CostPerGallon` and `MPG` on a slice in place. |
| `service/mpg_test.go` | Table-driven tests for the MPG algorithm + a "doesn't mutate input" guard. |
| `client/vehicle_client.go` | HTTP client for vehicle-service: timeout, one retry, typed errors. |
| `store/store.go` | Connection pool, `search_path` pinned to the `activity` schema. (Near-copy of vehicle-service's.) |
| `store/fuel_store.go` | `ListFuelEntries` (newest-first) and `CreateFuelEntry`. Casts `NUMERIC::double precision` for clean float64 scanning. |
| `handlers/respond.go` | JSON helpers. (Near-copy.) |
| `handlers/router.go` | Routes + the `FuelStore` / `VehicleValidator` interfaces the handlers depend on. |
| `handlers/fuel_handlers.go` | `List` and `Create`: path parsing, body validation, the vehicle-existence check, MPG enrichment of the response. |
| `handlers/fuel_handlers_test.go` | Handler tests with fake store + fake vehicle validator, incl. the fail-closed 503 case. |
| `main.go` | Config (adds `VEHICLE_SERVICE_URL`), wires the client, server lifecycle. |
| `migrations/000001_create_fuel_entries.{up,down}.sql` | The `activity.fuel_entries` table + a `(vehicle_id, odometer)` index. |
| `Dockerfile` / `.dockerignore` | Multi-stage build → distroless. |
| `docker-compose.yml` (updated) | Adds `activity-migrate` (one-shot) and `activity-service` (port 8082). |
| `scripts/test.sh` / `scripts/migrate.sh` (updated) | Now cover both services. |

---

## Design Decisions Made Beyond the Spec

- **`float64` for `gallons` and `total_cost`.** For a personal fuel log the
  rounding error is far below a cent and MPG is a float anyway. Queries do
  `NUMERIC::double precision` so the scan target is unambiguous. Real money
  handling would keep `NUMERIC` end-to-end (a decimal type or integer cents).
- **The inter-service call ships in M2, not M4.** The build order puts it in M4,
  but fuel-entry creation is the natural first place it's needed, and you asked
  specifically about the failure handling. M4 will add odometer reads for the
  maintenance "due" logic and (likely) a short-TTL response cache.
- **`activity-service` waits for its DB but not for vehicle-service.** Startup
  only blocks on Postgres. vehicle-service being down is handled per-request.
- **Reads don't check vehicle existence.** `GET .../fuel-entries` for an unknown
  vehicle returns `[]`, and keeps working when vehicle-service is down. Only the
  write path is gated ("fail closed on writes, degrade reads").
- **`POST` response includes derived fields.** After insert, the handler reloads
  the vehicle's full history and re-runs enrichment, so the created entry's
  response already shows its MPG if it closed an interval. If that reload fails,
  the entry is still saved and returned unenriched rather than 500.
- **Status codes:** `201` create, `400` malformed body (bad JSON, unparseable
  date), `422` well-formed-but-invalid (missing cost, `odometer <= 0`) *and*
  "vehicle does not exist", `503` + `Retry-After` when vehicle-service is
  unreachable.

---

## Verification (Actually Run)

Full stack under Compose. `vehicle` 1 = "Daily Driver".

```
POST .../vehicles/1/fuel-entries  full  odo 1000  10 gal  $35        → 201  mpg: null   (first full tank)
POST .../vehicles/1/fuel-entries  partial odo 1150 5 gal $3.50/gal   → 201  mpg: null   totalCost derived = 17.50
POST .../vehicles/1/fuel-entries  full  odo 1300   8 gal  $28        → 201  mpg: 23.08  = 300 / (5 + 8)
GET  .../vehicles/1/fuel-entries                                     → newest-first, MPG on entry 3 only
POST .../vehicles/999/fuel-entries                                   → 422  "vehicle does not exist"
POST .../vehicles/1/fuel-entries   (no cost field)                   → 422  "either totalCost or pricePerGallon is required"

# vehicle-service stopped:
POST .../vehicles/1/fuel-entries                                     → 503  Retry-After: 10   (~0.23s, one retry; entry NOT written)
GET  .../vehicles/1/fuel-entries                                     → 200  still returns the 3 stored entries

# vehicle-service restarted:
POST .../vehicles/1/fuel-entries  full  odo 1600  10 gal  $35        → 201  mpg: 30   = 300 / 10
```

`./scripts/test.sh` passes for both modules (MPG table tests + handler tests).
Confirmed `activity.fuel_entries` and `activity.schema_migrations` live in the
`activity` schema. Stack torn down with `down -v`.

---

## How to Run It Yourself

```bash
cd ~/Documents/Projects/Dipstick
./scripts/run-local.sh -d
curl -s localhost:8081/vehicles                       # vehicle-service
curl -s localhost:8082/vehicles/1/fuel-entries        # activity-service
./scripts/migrate.sh activity version                 # check migration state
./scripts/run-local.sh nuke
```

- vehicle-service: `localhost:8081`
- activity-service: `localhost:8082`
- Postgres: `localhost:5432` (`dipstick`/`dipstick`/`dipstick`)

---

## Open Items for Milestone 3

- **Maintenance entry CRUD + "due" logic.** `maintenance_entries` table (JSONB
  `parts_used`), `GET/POST /vehicles/{id}/maintenance-entries`, and the
  due-soon/overdue calculation comparing current odometer/date to the last
  entry's `next_due_odometer` / `next_due_date` per service type.
- **`GET /vehicles/{id}/stats`** (average MPG, total spend all-time / this year,
  MPG trend) — sketched in the API contract; likely M3 or a polish milestone.
- **The `parts_used` JSONB column** will be the next "custom Scanner/Valuer or
  `json.RawMessage`" decision.
