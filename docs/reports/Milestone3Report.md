# Dipstick — Milestone 3 Report: maintenance log + due-date logic

**Status:** Built and verified end-to-end. Maintenance entries (with JSONB parts)
are created and listed, `GET /due` computes due-soon/overdue across all vehicles
sorted by urgency, and the degraded path (vehicle-service down → date-based
checks only, with a warning) works.

---

## Concepts Introduced This Milestone

**A slice type over a JSONB column (`models.Parts`)**
`Parts []Part` implements `driver.Valuer` (marshal the whole slice to JSON bytes;
nil slice → SQL `NULL`) and `sql.Scanner` (unmarshal the column's bytes back).
Same boundary-interface pattern as `Date`, but the payload is structured. JSONB
is Postgres storing *parsed* JSON in a binary form it can index into — we only
read/write the whole value here, so we don't use that power yet, but the column
type leaves the door open.

**Postgres `DISTINCT ON`**
`SELECT DISTINCT ON (vehicle_id, service_type) ... ORDER BY vehicle_id,
service_type, date DESC, odometer DESC` returns exactly one row per
(vehicle, service type) group — the most recent — in a single query. The
`/due` endpoint needs "the latest entry for every service type on every
vehicle"; without `DISTINCT ON` that's a correlated subquery or a window
function. Backed by an index whose leading columns match the `ORDER BY`.

**Two-dimensional threshold logic**
A service can be due by **mileage** or by **date**, independently. `evaluateDue`
checks each dimension that has a target, marks overdue (`remaining <= 0`) or due
soon (`remaining <= buffer`), and takes the more urgent verdict. "Neither
dimension fires" → the item is left out of `/due` entirely.

**Graceful degradation of a read**
`GET /due` genuinely needs current odometers (from vehicle-service) for
mileage checks. Rather than 503 the whole endpoint when vehicle-service is down,
it runs the date-based checks it *can* do and attaches a `warnings` array. When
the vehicle list *is* available it also drops maintenance rows for vehicles that
no longer exist (orphans — there's no cascade delete).

**A `Deps` struct instead of a growing parameter list**
`handlers.NewRouter` now takes one `Deps{Fuel, Maintenance, Vehicles, DueConfig}`
struct. Adding the next handler won't churn the signature or every test call site.

---

## File Reference

| File | Role |
|---|---|
| `models/date.go` (edited) | Zero `Date` now ⇄ JSON `null` ⇄ SQL `NULL`; added `DaysUntil` and `Today`. Lets optional date fields be a plain `Date`. |
| `models/maintenance.go` | `Part`, `Parts` (JSONB Scanner/Valuer), `MaintenanceEntry`, `MaintenanceEntryInput`, `DueItem`, `DueStatus`. |
| `service/due.go` | `CalculateDue` (double loop + one sort), `evaluateDue` (per-service scoring), `urgency` (single sortable number), `DueConfig`. Pure, no I/O. |
| `service/due_test.go` | Table-driven: mileage/date × due-soon/overdue/far/edge, both-targets, odometer-unknown, cross-vehicle sort. |
| `store/maintenance_store.go` | `ListMaintenanceEntries`, `CreateMaintenanceEntry`, `LatestMaintenancePerService` (the `DISTINCT ON` query). |
| `client/vehicle_client.go` (rewritten) | Added `ListVehicles`; factored the retry/timeout logic into a shared `getJSON` used by both methods. |
| `handlers/router.go` (rewritten) | `Deps` struct, `MaintenanceStore` + `VehicleAPI` interfaces, routes for maintenance and `/due`. |
| `handlers/maintenance_handlers.go` | `List` / `Create` — path parsing, body validation (incl. parts, next-due sanity), the fail-closed vehicle check. |
| `handlers/due_handlers.go` | `GET /due` — loads latest-per-service, fetches odometers (degrading on failure), groups by vehicle, calls `CalculateDue`, wraps in `{items, generatedAt, warnings}`. |
| `handlers/maintenance_handlers_test.go` | Create (with parts), validation table, `/due` across vehicles, `/due` degraded path. |
| `handlers/fuel_handlers_test.go` (edited) | Fake renamed to `fakeVehicleAPI` with `ListVehicles`; `NewRouter(Deps{...})`. |
| `main.go` (edited) | Reads `DUE_MILES_BUFFER` / `DUE_DAYS_BUFFER`; builds `Deps`. |
| `migrations/000002_create_maintenance_entries.{up,down}.sql` | The table + `(vehicle_id, service_type, date DESC, odometer DESC)` index. |

---

## Design Decisions Made Beyond the Spec

- **`Date` zero-value means null.** Simpler than `*Date` everywhere (`database/sql`
  handles pointer-to-Scanner-type awkwardly). Backward-compatible: fuel's `date`
  is `NOT NULL` so it's never zero coming from the DB.
- **Cross-dimension urgency is `remaining / buffer`, worst wins.** This makes
  "300 miles left" and "9 days left" roughly comparable. A consequence seen in
  testing: a service whose *date* target is years past produces a large negative
  score and sorts above a mileage-overdue one. That's defensible (2 years overdue
  *is* more urgent) but it is a heuristic, not a law — the buffers are the knob.
- **No priority queue / heap.** The architecture doc floats one. `/due` has to
  examine every service type once to know what's due, and the output is a sorted
  list — a heap only pays off for repeated "give me the next one" peeks without
  recomputing, which this endpoint doesn't do. A sort is the right tool; adding a
  heap would be cargo-culting.
- **`/due` degrades instead of failing** when vehicle-service is down (date checks
  only + `warnings`). Contrast with fuel/maintenance *creation*, which fails
  closed — writes need certainty, this read doesn't.
- **Orphan handling:** when the vehicle list is available, `/due` skips
  maintenance rows for vehicles vehicle-service no longer knows about. Proper
  cleanup of those rows is still a Milestone 4 item.
- **Buffers are env-configurable** (`DUE_MILES_BUFFER`=500, `DUE_DAYS_BUFFER`=14).
- **Validation:** `nextDueOdometer` must exceed the entry's odometer;
  `nextDueDate` must be after the entry's date; every part needs a name; costs
  can't be negative.

---

## Verification (Actually Run)

Full stack under Compose. Vehicle 1 @ 50000 mi, vehicle 2 @ 30000 mi.

```
POST v1/maintenance-entries  oil change  odo 45000  parts:[filter 12.50, oil 34.00]
                             nextDueOdometer 50000  nextDueDate 2024-07-15         → 201
POST v1/maintenance-entries  tire rotation  odo 42000  nextDueOdometer 48000        → 201
POST v2/maintenance-entries  brake pads  odo 18000  nextDueOdometer 30200           → 201
GET  v1/maintenance-entries                                → newest-first, parts round-trip through JSONB
POST v1/maintenance-entries  nextDueOdometer == odometer   → 422

GET /due:
  1. v1 oil change    overdue   (milesRemaining 0, daysRemaining -780)
  2. v1 tire rotation overdue   (milesRemaining -2000)
  3. v2 brake pads    due_soon  (milesRemaining 200)

# vehicle-service stopped:
GET /due → 200, warnings:[...unreachable...], only the date-based "oil change" item remains
```

`./scripts/test.sh` green for both modules. `activity.maintenance_entries` +
`activity.schema_migrations` confirmed at version 2. Stack torn down with `down -v`.

---

## How to Run It Yourself

```bash
cd ~/Documents/Projects/Dipstick
./scripts/run-local.sh -d
curl -s localhost:8082/vehicles/1/maintenance-entries
curl -s localhost:8082/due | python3 -m json.tool
./scripts/migrate.sh activity version      # -> 2
./scripts/run-local.sh nuke
```

---

## Open Items for Milestone 4

- **The formal inter-service milestone.** Most of it (the HTTP client, timeout,
  retry, fail-closed) already shipped in M2/M3. What's left:
  - A short-TTL in-memory cache for `GET /vehicles/{id}` / `GET /vehicles` so a
    burst of writes or a brief blip doesn't hammer vehicle-service.
  - **Orphan cleanup**: when a vehicle is deleted, its fuel + maintenance rows
    should go too. Options: vehicle-service best-effort calls activity-service on
    delete; or activity-service reconciles periodically against the vehicle list.
- **`GET /vehicles/{id}/stats`** (avg MPG, total spend all-time / this year, MPG
  trend) — still unbuilt; fits M4 or the polish milestone.
