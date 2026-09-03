# Dipstick — Product Spec

## 1. Overview

A personal full-stack app for tracking vehicle maintenance and fuel fill-ups,
replacing notebook/Notes-app tracking. iOS client (SwiftUI) talking to a real
backend API over the network. Single user, no accounts, no sharing.

**Secondary goal:** this project doubles as deliberate skill-building toward a
specific job description (Go, SQL, microservices, Docker, CI/CD, networking). Some
architectural choices below favor "get real reps on X" over "simplest possible way
to ship this app" — that trade-off is intentional.

**Core problems it solves:**
- DIY maintenance records for a project car are scattered and unorganized.
- Some DIY maintenance on a daily driver (oil changes, tire rotations) also needs tracking.
- Fuel fill-ups are logged manually, and MPG is calculated by hand every time.

## 2. Users & Scope

- Single user, personal use only.
- Manages 2+ vehicles (support an arbitrary number, not hardcoded to exactly two).
- No login/auth needed for v1 — single-user API, no multi-tenant concerns.

## 3. System Shape

- **Client**: iOS app, SwiftUI, talks to the backend over HTTPS/JSON.
- **Backend**: two Go services (see Architecture doc) backed by Postgres.
- **No offline mode for v1** — the app expects network connectivity to the backend.
  (A local cache/offline queue is a good v2 addition, not required now.)

## 4. Core Features (MVP)

### 4.1 Vehicles
- Add / edit / delete a vehicle: name (e.g. "Daily Driver", "Project Car"), year, make,
  model, optional VIN, current odometer reading.
- Vehicle list is the home screen; tapping one opens its detail view.

### 4.2 Fuel Log
- Add a fuel entry per vehicle: date, odometer reading, gallons purchased, total cost
  (or price/gallon — derive the other), whether this was a **full tank** fill-up,
  optional station name/notes.
- **Automatic MPG calculation**: computed between two consecutive *full-tank* fill-ups
  as (miles driven since last full tank) / (gallons used since last full tank).
  Partial fill-ups still get logged but are excluded from MPG math (flagged in the UI
  as "partial — not used for MPG").
- Fuel history list per vehicle, most recent first, showing date, gallons, cost,
  cost/gallon, and MPG (when calculable).
- Simple stats view: average MPG over time, total fuel spend (all-time, this year),
  trend line chart of MPG per fill-up.

### 4.3 Maintenance Log
- Add a maintenance entry per vehicle: date, odometer, service type (oil change, tire
  rotation, brake pads, filter, fluid, other/custom text), cost, parts used
  (repeatable "part name + cost" rows), notes.
- Optionally set a "next due" for that service type, either by mileage (e.g. every
  5,000 mi) or by date (e.g. every 6 months), or both.
- Maintenance history list per vehicle, most recent first.
- **Upcoming/Due view**: surfaces any service that's due soon or overdue, across all
  vehicles, based on current odometer vs. last logged service + interval.

### 4.4 Home / Dashboard
- List of vehicles with at-a-glance info: last fuel-up MPG, next maintenance due.
- Tapping a vehicle goes to its detail screen with tabs: Fuel, Maintenance, Stats.

## 5. Out of Scope for MVP (future ideas — do not build yet)
- Photo attachments for receipts.
- Multi-user / sharing / accounts.
- Push notification reminders for due maintenance (v1 just shows it in-app).
- Exporting to CSV/PDF.
- Offline mode / local caching on the client.
- Android/other platforms.
- **Automatic city/highway driving split per tank** (see 5.1 below) — noted for v2,
  not part of MVP.

### 5.1 Future: Automatic City/Highway Split (v2 idea)
Instead of manually estimating what % of a tank was highway vs. city driving (as
other fuel-tracking apps require), use the phone's location/motion data to compute
it automatically. Rough approach when this gets picked up:
- Use `CoreLocation` speed data during a trip; classify sustained high-speed,
  low-variance segments as "highway," lower/variable-speed segments as "city."
- Use `CoreMotion` to detect "in a vehicle" state at all vs. walking/stationary.
- **Open problem to solve first**: how the app knows *which* of your vehicles (or
  neither — e.g. a ride/rental) a given trip belongs to. Likely needs either a
  manual "start trip for [vehicle]" toggle, or auto-detection via Bluetooth/CarPlay
  pairing to that specific vehicle.
- Requires background location permission — real battery and privacy trade-offs to
  weigh before committing to this.

## 6. Success Criteria
- Logging a fuel stop takes under 30 seconds.
- MPG is always computed automatically, never by hand.
- Maintenance history for the project car is fully organized and searchable by vehicle.
- Backend is deployed and reachable over the internet via a real domain.
- Pipeline: pushing to `main` runs tests and deploys automatically with no manual steps.
