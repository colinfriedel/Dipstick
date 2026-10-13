# Dipstick — Handoff & Build Plan (v2 plan: simplest thing that works)

Give this file to Claude Code (drop it in `docs/` at the repo root) or paste it into a
fresh chat. It supersedes the earlier "Go microservices + Postgres + cloud" plan.
Everything below is written so a reader with zero prior context can plan and build.

---

## 1. What this is

**Dipstick** is a personal iPhone app for one user (me) to track maintenance and fuel
fill-ups for my cars. I want to actually use it every week, so the priority is
"useful and fast to log into," not résumé coverage.

**My cars**
- **Daily driver**: reliable; I do some of the work myself (oil changes, tire rotations)
  and want those tracked.
- **Project car**: I do *all* scheduled maintenance myself and want a well-organized
  history (currently scattered across paper notebooks and iPhone Notes).

**Pain points to kill**
1. Maintenance records live in notebooks/Notes and aren't searchable or organized.
2. Fuel stops are logged in Notes and I calculate MPG by hand every time.

## 2. The key decision: drop the backend

The old plan had an iOS client + two Go services + Postgres + Docker + CI/CD + cloud
hosting. That was built to practice job-posting skills. **I no longer need that.** For a
single-user personal app it's pure overhead (servers to host, deploy, secure, pay for).

**New architecture: a single native iOS app. No backend.**
- Swift + SwiftUI
- **SwiftData** for local persistence
- **iCloud sync via SwiftData's CloudKit support** (so data survives a phone
  replacement and is backed up) — can be switched on after the local version works
- Swift Charts for the MPG trend chart
- No server, no auth, no accounts, no network code

### Starting fresh
This is a brand-new repo. The earlier backend attempt (Go services, Postgres, Docker)
has been deleted and is not coming back; ignore any older Spec/Architecture docs or
references to `backend/` if you ever see them. The repo root is the Xcode project itself
(single iOS app, no `ios/` subfolder), created with SwiftData as the storage option.
- The Xcode template includes a sample `Item` model and list view; replace them with
  the real models below rather than building on top of them.
- Work on a feature branch per milestone and commit when I ask.

## 3. MVP features

### Vehicles
- Add / edit / delete a vehicle: nickname ("Daily Driver", "Project Car"), year, make,
  model, optional VIN, current odometer. Support any number of vehicles, not exactly two.
- Home screen = vehicle list with at-a-glance info (latest MPG, next maintenance due).
- Vehicle detail with three sections/tabs: **Fuel**, **Maintenance**, **Stats**.

### Fuel log (speed matters: logging a fill-up should take < 30 seconds)
- Fields: date (default now), odometer, gallons, total cost *or* price/gallon (derive
  the other), **full tank?** toggle (default on), optional station, optional notes.
- Pre-fill odometer from the vehicle's last known reading; keep the form short.
- **MPG is automatic.** See the algorithm in section 5.
- History list, newest first: date, gallons, cost, $/gal, MPG (or "partial fill — not
  used for MPG").
- Stats: average MPG (all-time / recent), MPG-per-fill-up trend chart, fuel spend
  (all-time and this year).

### Maintenance log
- Fields: date, odometer, service type (oil change, tire rotation, brake pads, air
  filter, fluids, other/custom), cost, parts used (repeatable "part name + cost" rows),
  notes.
- Optional **"next due"** per entry: by mileage interval, by time interval, or both.
- History list per vehicle, newest first, filterable by service type and searchable
  (this is the "organized records for the project car" requirement).
- **Due view**: services due soon or overdue across all vehicles, computed from current
  odometer vs. last logged service + interval. Show it on the home screen.

## 4. Data model (SwiftData, CloudKit-compatible from day one)

CloudKit sync constraints — respect these now so enabling sync later is a config change:
every property has a default value or is optional; relationships are optional; **no
`@Attribute(.unique)`**; no non-optional relationships.

```swift
@Model final class Vehicle {
    var name: String = ""
    var year: Int?
    var make: String?
    var model: String?
    var vin: String?
    var currentOdometer: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \FuelEntry.vehicle)
    var fuelEntries: [FuelEntry]? = []
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceEntry.vehicle)
    var maintenanceEntries: [MaintenanceEntry]? = []
}

@Model final class FuelEntry {
    var date: Date = Date()
    var odometer: Int = 0
    var gallons: Double = 0
    var totalCost: Double = 0
    var isFullTank: Bool = true
    var station: String?
    var notes: String?
    var vehicle: Vehicle?
}

@Model final class MaintenanceEntry {
    var date: Date = Date()
    var odometer: Int = 0
    var serviceType: String = ""
    var cost: Double = 0
    var notes: String?
    var nextDueOdometer: Int?
    var nextDueDate: Date?
    var vehicle: Vehicle?
    @Relationship(deleteRule: .cascade, inverse: \PartUsed.entry)
    var parts: [PartUsed]? = []
}

@Model final class PartUsed {
    var name: String = ""
    var cost: Double = 0
    var entry: MaintenanceEntry?
}
```

(Parts are a small child model rather than a `[String]` so each part can carry a cost.)

## 5. Core logic (put in plain Swift types with unit tests — no UI dependency)

**MPG** — computed between consecutive **full-tank** fill-ups for one vehicle, sorted by
odometer:
- Miles = current full-tank odometer − previous full-tank odometer.
- Gallons = gallons from the current full-tank entry **plus any partial fill-ups logged
  between them**.
- MPG = miles / gallons. Partial fills only contribute gallons to the next full-tank
  calculation; they don't get their own MPG.
- Edge cases to test: first-ever entry (no MPG), several partials in a row, odometer
  that goes backwards or equals the previous (reject or flag in the form), entries
  logged out of order (always sort, never assume insertion order).

**Maintenance due** — for each vehicle + service type, look at the most recent entry's
`nextDueOdometer` / `nextDueDate`; compare to the vehicle's current odometer (latest of
`currentOdometer` and any logged odometer) and today. States: ok / due soon (tunable
constants, e.g. 500 mi or 14 days) / overdue.

Keep `Vehicle.currentOdometer` updated whenever a fuel or maintenance entry with a
higher odometer is saved.

## 6. Suggested structure

```
Dipstick/                      (inside the repo root, next to Dipstick.xcodeproj)
  DipstickApp.swift            (modelContainer setup)
  Models/                      (the @Model types above)
  Logic/                       (MPGCalculator, MaintenanceDueCalculator — pure, tested)
  Views/
    Vehicles/                  (list, detail, add/edit)
    Fuel/                      (history, add entry)
    Maintenance/               (history, add entry, due view)
    Stats/                     (summary + Swift Charts MPG trend)
```
Use SwiftUI's `@Query` and `@Environment(\.modelContext)` directly in views for simple
lists; only introduce view models where there's real logic. Don't over-architect.

## 7. Build order

1. **Foundation**: remove the template's sample `Item` code, add the Vehicle model and
   add/list/edit/delete UI, confirm `.gitignore` covers Xcode junk. Run on simulator.
2. **Fuel log**: model, add-entry form (fast), history list, `MPGCalculator` + unit tests.
3. **Maintenance log**: model, add-entry form with parts and next-due, history list with
   filter/search.
4. **Due view + home screen**: due-soon/overdue computation, home list with at-a-glance
   info.
5. **Stats**: summary numbers + MPG trend chart.
6. **Run it on my real iPhone** and import my existing records (consider a simple CSV
   import or just manual entry of recent history — ask me).
7. **iCloud sync**: add the CloudKit capability and container, verify on a second
   device/reinstall.
8. Polish: validation, empty states, number formatting, app icon.

Get to step 6 as fast as possible — real use will surface what's actually missing.

## 8. Practical gotchas to flag early

- **Apple Developer account**: iCloud/CloudKit requires a paid Apple Developer Program
  membership ($99/yr). With a free account I can still run on my own phone, but the build
  must be re-signed about every 7 days and iCloud sync is unavailable. Decide before
  step 6–7.
- **Deployment target**: SwiftData needs iOS 17+. That also satisfies my "support a
  couple years back" wish.
- Units: US gallons / miles / dollars. Make that a single formatting layer so a later
  km/L option is easy.

## 9. Later ideas (not MVP, don't build yet)

- **Automatic city/highway split per tank** using phone location/motion instead of
  manually estimating it, which other apps make you do. Rough approach: CoreLocation
  speed (sustained high speed with low variance = highway), CoreMotion to confirm
  "in a vehicle." Open problem: knowing *which* car (or neither — a ride/rental)
  a trip belongs to; options are a manual "start trip for [vehicle]" toggle or
  Bluetooth/CarPlay detection. Needs background location permission (battery/privacy
  trade-offs).
- Receipt/part photos on entries.
- Local notifications for due maintenance.
- CSV export.
- Home-screen widget showing next due service.
- **Import the maintenance schedule from the owner's manual**, for any car: most manuals
  are online as PDFs or other formats. The app reads the schedule and sets up the
  service types and intervals, then tracks due dates from there (fits the existing
  interval-based "next due" and custom service types). Open questions: on-device PDF
  parsing vs. a hosted service (the app has no backend), manuals that list both
  "normal" and "severe" schedules, and letting the user review before anything is
  saved.

## 10. How I want to work

- I have some Xcode/Swift experience and want to **understand what's being built**,
  not just receive working code. Briefly explain new concepts (SwiftData, `@Query`,
  CloudKit constraints) and non-obvious decisions, and say in a sentence what each new
  file does. Keep explanations short; don't lecture.
- Prefer clear, idiomatic code over clever code.
- Small, reviewable steps. Don't commit unless I ask.
- Ask before assuming if something here is ambiguous or you think a decision above
  is wrong.

---

## Kickoff prompt (paste this into Claude Code from the repo root)

```
I'm building "Dipstick," a personal iPhone app (SwiftUI + SwiftData, no backend) for
tracking maintenance and fuel fill-ups on my cars, with automatic MPG calculation.
Read docs/Dipstick_Handoff.md fully first. This is a fresh repo; the Xcode project
(created with SwiftData storage) lives at the repo root.

Then do Step 1 of the build order: remove the template's sample Item code, build the
Vehicle model plus add/list/edit/delete UI, and check that .gitignore covers Xcode
junk (xcuserdata, DerivedData, .DS_Store). Work on a feature branch.

Before coding, tell me your plan in a few bullets and ask any questions you have. As you
go, briefly explain new concepts and what each file does, but keep it concise.
```
