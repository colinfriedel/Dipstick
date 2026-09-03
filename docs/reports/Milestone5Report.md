# Dipstick — Milestone 5 Report: iOS vehicle list & detail

**Status:** Built and verified end-to-end. The SwiftUI app builds, its 9 view-model
unit tests pass, and it loads/creates/edits/deletes vehicles against a live
vehicle-service (confirmed in the simulator and by a UI test).

---

## Concepts Introduced This Milestone

**MVVM in SwiftUI**
- *Model* — `Vehicle` / `VehicleInput`: plain `Codable` structs, no behavior.
- *View* — `VehicleListView` etc.: declarative UI, binds to a view model, no
  networking or error handling of its own.
- *ViewModel* — `VehicleListViewModel` / `VehicleFormViewModel`: hold the screen's
  state and the actions on it, call the repository, translate errors to strings.

**`@Observable` + `@State`**
The modern observation model (iOS 17+). A view model is a plain `@Observable`
class; the view *owns* it with `@State private var viewModel` and reads its
properties directly — SwiftUI tracks which properties a view actually reads and
re-renders only when those change. No `ObservableObject` / `@Published` /
`@StateObject`.

**`async`/`await` networking**
`try await session.data(for: request)` in `APIClient`. Views drive it with
`.task { await viewModel.load() }` (runs on appear, cancelled on disappear) and
`.refreshable { }` (pull to refresh). No completion handlers, no Combine.

**Protocol-based dependency injection**
View models depend on a `VehicleRepository` *protocol*, not a concrete type.
Production wires in `APIVehicleRepository` (HTTP); tests and `#Preview`s wire in
`InMemoryVehicleRepository` (a fake in-memory server). This is what makes the
view models unit-testable without a network.

**`Codable` ⇄ JSON**
`Vehicle`'s property names match the API's camelCase keys exactly, so there are
no `CodingKeys`. `nil` optionals are omitted by the synthesized encoder, which
the backend reads as "not set".

**App Transport Security**
iOS blocks cleartext HTTP by default. `Info.plist` adds a narrow exception for
`localhost` so the simulator can reach the dev backend. Production uses HTTPS and
none of it applies.

**Xcode file-system-synchronized groups**
The project auto-includes any file under `Dipstick/`, so new `.swift` files and
subfolders need no `project.pbxproj` editing. The one exception: `Info.plist`
had to live *outside* that folder (at the project root) or it got copied twice —
once as a resource, once as the processed Info.plist.

---

## File Reference

| File | Role |
|---|---|
| `Info.plist` | ATS exception for `http://localhost`. Merged with Xcode's generated plist. |
| `Dipstick.xcodeproj/project.pbxproj` | One setting added: `INFOPLIST_FILE = Info.plist` (Debug + Release). |
| `DipstickApp.swift` | Root scene → `VehicleListView`. |
| `Support/AppEnvironment.swift` | The backend URL (overridable via `DIPSTICK_VEHICLE_URL`) and the shared live repository. |
| `Models/Vehicle.swift` | `Vehicle` (row) + `VehicleInput` (request body) + a `descriptiveTitle` helper. |
| `Networking/APIClient.swift` | Generic async `URLSession` wrapper: build request, send, validate status, decode; pulls `{"error": …}` out of failures. |
| `Networking/APIError.swift` | One error enum with user-facing `localizedDescription` for each failure kind. |
| `Networking/VehicleRepository.swift` | The `VehicleRepository` protocol, `APIVehicleRepository` (live), `InMemoryVehicleRepository` (DEBUG-only fake). |
| `Features/VehicleList/VehicleListViewModel.swift` | Load (sorted), optimistic delete with rollback, load/action error state. |
| `Features/VehicleList/VehicleListView.swift` | `NavigationStack` + `List`, loading / error / empty states, pull-to-refresh, add sheet, swipe-to-delete. |
| `Features/VehicleDetail/VehicleDetailView.swift` | Read-only detail, Edit sheet, Delete with confirmation. Placeholder where the Fuel/Maintenance/Stats tabs will go (M6). |
| `Features/VehicleForm/VehicleFormViewModel.swift` | Field text as `String`s, validation (`canSave`), `String` → `VehicleInput` conversion, create-vs-update. |
| `Features/VehicleForm/VehicleFormView.swift` | The modal `Form`, Save/Cancel, saving overlay. |
| `DipstickTests/VehicleListViewModelTests.swift` | Sort, failure surfacing, delete + rollback (Swift Testing). |
| `DipstickTests/VehicleFormViewModelTests.swift` | Trim/nil-out fields, edit prefill, update path, blank-name guard, bad-number fallback. |
| `DipstickUITests/AddVehicleUITests.swift` | End-to-end: tap +, fill the form, save, assert the row appears. Needs the backend running. |

---

## Design Decisions Made Beyond the Spec

- **Everything `@MainActor`** — the project's Xcode-26 default
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Network calls are *initiated*
  from the main actor, but `await session.data(...)` suspends without blocking
  the UI, so this is fine for a single-user app and much simpler to read than
  hand-managing actor hops. Default arguments that touch `@MainActor` state
  don't compile, so view inits take an optional dependency (`nil`) and resolve it
  in the body.
- **`@Observable`, not `ObservableObject`** — less boilerplate, we target iOS 26.
- **Optimistic delete** — the row disappears immediately; if the server call
  fails, the list is restored and an alert explains. Feels instant, stays correct.
- **The detail screen shows info + edit/delete only.** The spec's
  Fuel/Maintenance/Stats tabs need activity-service and land in M6. A one-line
  placeholder marks the spot rather than showing empty tabs.
- **Base URL overridable** via `DIPSTICK_VEHICLE_URL` (for pointing at a deployed
  backend after M8), defaulting to `http://localhost:8081`.
- **`InMemoryVehicleRepository` ships in the app binary under `#if DEBUG`** — it's
  small, and keeping it in the app target (not the test target) lets both
  `#Preview`s and unit tests use it.
- **`Info.plist` lives at the project root**, not in the source folder, to avoid
  the synchronized group copying it twice.

---

## Verification (Actually Run)

- `xcodebuild build` — **BUILD SUCCEEDED** (iPhone 17 simulator, iOS 26).
- `xcodebuild test -only-testing:DipstickTests` — **9 tests passed** (view-model
  logic: sorting, error surfacing, optimistic delete + rollback, form
  validation, edit prefill, create/update paths).
- `xcodebuild test -only-testing:DipstickUITests/AddVehicleUITests` — **passed**:
  launched the app, tapped +, filled the form, saved, and the new vehicle
  appeared in the list — against the live Dockerized backend.
- Ran in the simulator against `docker compose up`: the list rendered both
  seeded vehicles with year/make/model and formatted odometer (screenshot in the
  PR).

---

## How to Run It Yourself

```bash
# 1. backend
cd ~/Documents/Projects/Dipstick && ./scripts/run-local.sh -d

# 2. app: open in Xcode and run on a simulator
open ios/Dipstick/Dipstick.xcodeproj
#    (Cmd-R with an iPhone simulator selected)
```

The app talks to `http://localhost:8081`. Add a vehicle with **+**, tap a row for
detail, **Edit** to change it, swipe or use the detail screen to delete.

---

## Open Items for Milestone 6

- **Fuel + maintenance screens** in the app, calling activity-service
  (`localhost:8082`): the fuel log with MPG, the maintenance log, and the `/due`
  view. This is where the detail screen gets its real tabs.
- **`GET /vehicles/{id}/stats`** on the backend — still unbuilt; the stats tab
  will need it.
- The at-a-glance "last MPG / next due" on the vehicle list rows (spec 4.4) —
  needs activity-service, so it comes with M6.
