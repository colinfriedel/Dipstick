# Dipstick — Milestone 6 Report: iOS fuel & maintenance screens

**Status:** Built and verified end-to-end. The vehicle detail screen now has
**Fuel / Maintenance / Stats** tabs backed by activity-service; a UI test logs a
fill-up through the form and screenshots all three tabs against the live backend.
29 unit tests + 2 UI tests pass.

---

## Concepts Introduced This Milestone

**Segmented `Picker` to switch sub-views**
`VehicleDetailView` holds a `@State private var tab` and a `Picker(...)
.pickerStyle(.segmented)`; the body `switch`es on it to show `FuelLogView`,
`MaintenanceLogView`, or `VehicleStatsView`. The two log view models are created
once (in the detail view's `init`) and live for the whole screen, so switching
tabs doesn't refetch.

**`DatePicker` and `Date` ⇄ `CalendarDate` at the form boundary**
`DatePicker` binds to a `Date`. The API wants `"YYYY-MM-DD"`. The form view
models keep a `Date` for the picker and convert with `CalendarDate(date)` only
when building the request body.

**A self-`Codable` type for a non-standard date format**
`CalendarDate` decodes/encodes as its own `"YYYY-MM-DD"` string
(`init(from:)` / `encode(to:)` on a `singleValueContainer`), because
`JSONDecoder`'s built-in `Date` strategies don't match — and the `/due`
response mixes that format with an RFC3339 `generatedAt`, so a global
`dateDecodingStrategy` wouldn't work anyway.

**Dynamic form rows**
The maintenance form's parts list: `ForEach($viewModel.parts) { $part in … }`
with `.onDelete` and an "Add part" button that appends `Part(name: "", cost: 0)`.
Editing binds straight through `$part.name` / `$part.cost`.

**Client-side derived stats**
`FuelStats.init(entries:)` is a few `reduce`/`filter`/`compactMap` passes over
the fuel entries the Fuel tab already loaded — total spend, this-year spend,
mean and max of the MPG values the backend computed.

---

## File Reference

| File | Role |
|---|---|
| `Models/CalendarDate.swift` | Calendar-day type; self-`Codable` as `"YYYY-MM-DD"`; `Comparable`; `Date` conversion + display string. |
| `Models/FuelEntry.swift` | `FuelEntry` (+ backend-computed `costPerGallon` / `mpg?`) and `FuelEntryInput`. |
| `Models/MaintenanceEntry.swift` | `MaintenanceEntry`, `MaintenanceEntryInput`, `Part` (client-only `id` for `ForEach`, excluded from JSON), `ServiceType.common` quick-picks. |
| `Models/DueItem.swift` | `DueItem` / `DueResponse` — modeled now; the `/due` dashboard UI is M9. |
| `Networking/ActivityRepository.swift` | Protocol + `APIActivityRepository` (HTTP) + `InMemoryActivityRepository` (DEBUG fake with sample data). |
| `Support/AppEnvironment.swift` | Now resolves **two** service URLs (vehicle + activity), each override → env var → default. |
| `Support/Formatting.swift` | `.money` and `.oneDecimal` format styles; `String.nilIfBlank`. |
| `Features/FuelLog/FuelLogViewModel.swift` | Loads one vehicle's fuel entries. |
| `Features/FuelLog/FuelLogView.swift` | Fuel tab: list with MPG / "partial — not used for MPG" per row, pull-to-refresh, add sheet. |
| `Features/FuelLog/FuelEntryFormViewModel.swift` | Fields as strings, `total`-vs-`per gallon` cost mode, validation, `→ FuelEntryInput`. |
| `Features/FuelLog/FuelEntryFormView.swift` | The "Log Fill-up" form. |
| `Features/MaintenanceLog/MaintenanceLogViewModel.swift` | Loads one vehicle's maintenance entries. |
| `Features/MaintenanceLog/MaintenanceLogView.swift` | Maintenance tab: rows with parts + "Next due" chip. |
| `Features/MaintenanceLog/MaintenanceEntryFormViewModel.swift` | Service-type picker (+ custom), parts add/remove, next-due-by-mileage/date toggles, validation mirroring the backend. |
| `Features/MaintenanceLog/MaintenanceEntryFormView.swift` | The "Log Service" form. |
| `Features/Stats/FuelStats.swift` | Client-computed summary struct. |
| `Features/Stats/VehicleStatsView.swift` | Stats tab: economy + spending rows, "trend chart coming later" note. |
| `Features/VehicleDetail/VehicleDetailView.swift` | Rewritten: compact header + segmented tabs + Edit/Delete moved to a toolbar menu. |
| `Features/Settings/ServerSettingsView.swift` | Now two URL fields (vehicle + activity). |
| `DipstickTests/*` | `CalendarDateTests`, `FuelStatsTests`, `ActivityFormViewModelTests` (fuel + maintenance). |
| `DipstickUITests/ActivityScreensUITests.swift` | Navigate to a vehicle, screenshot each tab, log a fill-up, verify it lands. |

---

## Design Decisions Made Beyond the Spec

- **Stats is a client-computed summary, not the server `/stats` endpoint.** The
  build order puts "stats/MPG chart" in Milestone 9. M6 shows the headline
  numbers (which fall straight out of the fuel list) and marks the trend chart as
  pending. `GET /vehicles/{id}/stats` is still unbuilt.
- **`/due` is modeled but not shown.** `DueItem` / `DueResponse` and
  `ActivityRepository.due()` are in place so M9's dashboard just wires up UI. No
  screen uses them yet.
- **Two configurable service URLs**, not one derived from the other — they'll
  likely be different hosts once deployed.
- **The two log view models are owned by `VehicleDetailView`** and stay alive
  across tab switches (Stats reuses the Fuel view model's data — no second fetch).
- **`Part.id` is a client-only `UUID`** for `ForEach`, excluded from `CodingKeys`
  so it's never sent to or expected from the backend.
- **Currency uses the device locale** (`Locale.current.currency`), single value,
  no per-entry currency — fine for one user.
- **Edit/Delete moved into a toolbar `Menu`** to make room for the per-tab "+".

---

## Verification (Actually Run)

Full stack under `docker compose`. Seeded "Daily Driver" with 3 full-tank
fill-ups and 2 services (one with parts + next-due targets).

- `xcodebuild build` → **SUCCEEDED**.
- **29 unit tests pass** (`DipstickTests`): `CalendarDate` codable round-trip +
  comparison + bad-input rejection; `FuelStats` aggregation and this-year
  filtering and MPG-only averaging; fuel form validation + total/per-gallon cost
  modes; maintenance form validation (odometer, service type, next-due > current,
  next-due date > service date, part needs a name) + custom service type + parts
  add/remove — plus all of M5's.
- **UI test `ActivityScreensUITests` passes**: opened a vehicle, captured the
  Fuel tab, logged a fill-up through the form (`Save` → row appears), switched to
  Maintenance (captured), switched to Stats and confirmed "Average MPG" (captured)
  — against the live backend. Screenshots in the PR.
- Fuel rows show MPG badges (31.3 / 33 MPG) and cost/gal; the partial entry shows
  "partial — not used for MPG". Maintenance rows show the parts list and
  "Next due: 63,000 mi or May 4, 2024". Stats: Average 32.2, Best 33, all-time
  $160.15.

---

## How to Run It Yourself

```bash
./scripts/run-local.sh -d          # both services
# Xcode: run on a simulator or your phone (Settings > Server for a device)
# Tap a vehicle → Fuel / Maintenance / Stats
```

---

## Open Items for Milestone 7+

- **Milestone 7: CI/CD** — GitHub Actions running `go test ./...` for both
  services (and, if practical, `xcodebuild test` for the app), building the
  Docker images.
- **Milestone 8: deploy** — decided: free host, chosen for real-role learning
  (leaning Oracle Cloud Always Free VM + Docker Compose + Caddy for HTTPS, with
  real DNS; k3s as a stretch). Then the app defaults to the deployed HTTPS URL
  and works anywhere.
- **Milestone 9: polish** — `GET /vehicles/{id}/stats` + the MPG **trend chart**
  (Swift Charts); the vehicle-list **at-a-glance** row info (last MPG, next due)
  and a **`/due` dashboard** across all vehicles.
