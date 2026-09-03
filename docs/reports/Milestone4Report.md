# Dipstick — Milestone 4 Report: inter-service resilience

**Status:** Built and verified end-to-end. Vehicle lookups are cached with a
short TTL and ride out a brief vehicle-service outage; a background reconciler
deletes activity rows for vehicles that no longer exist, with a guard against
mass-deletion.

The build order calls M4 "wire up the inter-service call." That call itself
shipped in M2/M3 (HTTP client, timeout, retry, fail-closed writes, degrade-on-read
for `/due`). M4 is what makes that dependency *robust*.

---

## Concepts Introduced This Milestone

**The decorator pattern (`CachingVehicleClient`)**
A new type wraps `*VehicleClient` and implements the same method set
(`VehicleFetcher`). Handlers hold the wrapper and can't tell the difference —
they just make fewer network calls. Wrapping-to-add-behavior, without touching
the wrapped type or its callers.

**`sync.RWMutex`**
The cache is read on every request (a hit) and written rarely (a fill). `RWMutex`
lets any number of readers hold the lock at once, but a writer gets it
exclusively. `RLock`/`RUnlock` for lookups, `Lock`/`Unlock` for fills.

**Injectable clock for testing time**
`CachingVehicleClient` has a `now func() time.Time` field, defaulting to
`time.Now`. Tests set `c.now = func() time.Time { return clock }` and advance
`clock` by hand — TTL expiry and the stale-grace window are tested with zero
`time.Sleep`, so the suite stays fast and deterministic.

**Stale-while-error**
On a cache miss the wrapper calls the upstream. If that fails *transiently*
(`ErrVehicleServiceUnavailable`) and there's a cached value less than `TTL +
grace` old, it serves the stale value rather than the error. A hard `404` is
never masked this way.

**Background workers tied to a context**
The reconciler runs in its own goroutine: an initial pass, then a `time.Ticker`
loop with `select { case <-ctx.Done(): return; case <-ticker.C: ... }`. `main`
adds it to a `sync.WaitGroup` and calls `workers.Wait()` after `server.Shutdown`,
so the process doesn't exit mid-pass.

**`sql.Tx` (transactions)**
`DeleteActivityForVehicle` deletes from `fuel_entries` and `maintenance_entries`
inside one `BeginTx` / `Commit`. The `defer tx.Rollback()` idiom: a no-op if
Commit already ran, an undo if we return early with an error.

---

## File Reference

| File | Role |
|---|---|
| `client/cache.go` | `CachingVehicleClient` — TTL cache, stale-on-error, RWMutex, injectable clock. List fetches also warm the per-id cache. |
| `client/cache_test.go` | Hit within TTL, refetch after TTL, serve-stale-on-transient-error, error-when-too-old, disabled (TTL 0), list warms per-id. |
| `store/reconcile_store.go` | `DistinctActivityVehicleIDs` (UNION across both tables) and transactional `DeleteActivityForVehicle`. |
| `reconcile/reconcile.go` | `Reconciler` — the ticker loop, the empty-list guard, per-orphan delete. |
| `reconcile/reconcile_test.go` | Deletes orphans only, no-op when in sync, skips on empty list, skips when vehicle-service unavailable, continues past a delete error. |
| `main.go` (edited) | Builds raw + cached clients; handlers get cached, reconciler gets raw. Starts/stops the worker via `sync.WaitGroup`. New env vars. |
| `docker-compose.yml` (edited) | Sets `VEHICLE_CACHE_TTL=30s` and `RECONCILE_INTERVAL=30s` (short, so the behavior is observable in dev). |

---

## Design Decisions Made Beyond the Spec

- **Reconciliation loop, not a synchronous delete hook.** vehicle-service could
  call activity-service when a vehicle is deleted — but then the two services
  depend on *each other*. The loop keeps the arrow one-way (activity → vehicle)
  and is self-correcting no matter what failed. Cost: cleanup lags by up to one
  interval. `/due` already filters orphans at read time, so nothing user-facing
  waits on it. A synchronous hook could be added later purely for instant cleanup.
- **Empty-list guard.** If `ListVehicles` returns zero vehicles, the reconciler
  skips the whole pass. An empty "source of truth" almost always means something
  is broken, not that the user deleted their last car — and acting on it would
  delete every activity row. Any reconciliation loop that can mass-delete needs
  this check.
- **The reconciler uses the raw (uncached) client.** It's deciding what to
  delete; a stale list could briefly protect a genuine orphan (harmless, caught
  next pass) but it should still work from ground truth.
- **Stale grace = 1× TTL** (so values up to 2× TTL old may be served during an
  outage). Long enough to cover a short blip, short enough that a genuinely
  deleted vehicle isn't honored for long.
- **404s are never served stale.** "Doesn't exist" is a definitive answer; only
  "couldn't reach the service" triggers the fallback.
- **No cache eviction / LRU.** Entries are overwritten on refetch and ignored
  when stale; the map only ever holds as many vehicles as exist. Fine at this
  scale.
- **TTL 0 disables the cache; interval 0 disables the reconciler** — both are
  env-configurable (`VEHICLE_CACHE_TTL`, `RECONCILE_INTERVAL`).

---

## Verification (Actually Run)

Full stack under Compose (`RECONCILE_INTERVAL=30s`, `VEHICLE_CACHE_TTL=30s`).

**Orphan reconciliation:**
```
create vehicle 1 (Keeper) + vehicle 2 (ToDelete); add fuel to both, maintenance to 2
DELETE vehicle 2 from vehicle-service              → 204
wait one reconcile tick
  vehicle 2 fuel entries: 0    maintenance entries: 0
  vehicle 1 fuel entries: 1    (untouched)
log: "reconcile: removed 2 activity row(s) for orphaned vehicle 2"
```
The startup pass ran before any vehicle existed and correctly hit the guard:
`"reconcile: vehicle list is empty, skipping (refusing to treat that as 'delete everything')"`.

**Cache riding out an outage:**
```
POST fuel entry for vehicle 1                      → 201  (calls vehicle-service, caches it)
docker compose stop vehicle-service
POST fuel entry for vehicle 1 (cache still fresh)  → 201  (no upstream call needed)
wait 65s (past TTL + grace)
POST fuel entry for vehicle 1                      → 503  (cache too old to trust, upstream down)
```
While vehicle-service was down, the reconciler logged `"skipping this pass, could
not list vehicles"` each tick — it did not delete anything.

`./scripts/test.sh` green for both modules (6 new cache tests, 5 new reconciler tests).

---

## How to Run It Yourself

```bash
cd ~/Documents/Projects/Dipstick
./scripts/run-local.sh -d
# add a vehicle + some activity, then:
curl -s -XDELETE localhost:8081/vehicles/2
docker compose logs -f activity-service | grep reconcile   # watch it clean up within 30s
./scripts/run-local.sh nuke
```

---

## Open Items for Milestone 5+

- **Milestone 5–6: the iOS app.** SwiftUI + MVVM, `URLSession` + async/await,
  vehicle list/detail then fuel + maintenance screens.
- **`GET /vehicles/{id}/stats`** (avg MPG, total spend all-time / this year, MPG
  trend line) — still unbuilt. Natural fit for milestone 9 (polish) or just
  before the iOS stats screen needs it.
- **Milestone 7–8:** GitHub Actions CI (`go test ./...`, build + push images),
  then deploy + DNS + HTTPS.
