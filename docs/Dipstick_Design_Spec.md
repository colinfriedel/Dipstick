# Dipstick: Visual and UX Spec for Claude Code

Written for Claude Code. It describes how the existing app should look and flow. The functionality is already built; this is mostly a reskin plus a handful of UX changes. Mockups are on the "Dipstick Home Options" design canvas (boards listed per screen below). The mockups are HTML approximations: match the intent and the tokens, not the pixels.

**Rules for using this document**
- Do not invent data. Every number, date, cost, and color in the mockups is sample data unless listed under "Real data" at the end. Always show what the app actually has.
- Keep SwiftUI-native. Prefer system components (NavigationStack, Form-like custom layouts, Swift Charts, `@Query`) styled with the tokens below.
- Work in small steps, in the order under "Priorities". Do not commit unless asked.

---

## 1. Design direction: "instrument cluster"

Inspired by the red-backlit gauge cluster in Colin's 2003 RSX. Dark-mode first, flat near-black ground, panels with thin borders, monospace numerals, one accent color. No gradients, glows, or textures. Colin rejected backlit gradients as busy, and rejected a "sporty" display font for numbers.

### Color tokens
| Token | Value | Use |
|---|---|---|
| ground | #07080A | screen background |
| panel | #101216 | cards, list panels, inputs |
| panelBorder | #23272E | 1pt borders on panels |
| divider | #1C2026 | row separators inside panels |
| control | #171A1F, border #4A5260 (1.5pt) | big action buttons |
| controlSmall | #101216, border #2A2F37 | back/Edit/more buttons (44pt) |
| selected | fill #1E232B, border #343B46 | selected tab or chip (chips use the accent border) |
| text | #DCE6F2 | primary text |
| muted | #8A94A3 | secondary text, labels |
| faint | #5B6676 | placeholders, neutral chart bars |
| accent | #FF6A2B | user-tweakable (alternates: #4FD1C5, #7CA8FF, #FFB000) |
| amber | #FFB000 | odometer digits, "due soon" |
| red | #FF5A4A (pill bg #2A1210) | overdue, errors, due-count pill |
| lcdGhost | #2A2108 | the faint "888888" behind odometer digits |

Make the accent a single app-wide setting, defaulting to #FF6A2B. Light mode and Dynamic Type must still work: provide a light palette with the same roles, and do not hard-code point sizes without scaling.

### Typography
- **Chakra Petch** (600 for headings and buttons, 500 for body) for UI text. **Share Tech Mono** for all numerals that are readouts: odometer, MPG, costs, gallons. Both are open-license Google Fonts; bundle them. Use `Font.custom(_, size:, relativeTo:)` so Dynamic Type works.
- Small caps labels: 10pt, letter-spacing about 1.5, color muted, uppercase ("CITY", "ODOMETER").
- Section titles: 12pt semibold, letter-spacing about 2, muted, uppercase ("FILL-UPS").
- Numerals in the mono face use **negative letter-spacing** (about -1 at 30pt) and the decimal point is pulled in with negative horizontal padding (about -3 to -4pt around the "."), because the monospace face gives the period a full cell. Build one reusable `MonoNumber` view that does this and takes a size.
- Every MPG number is followed by a small "mpg" unit (11pt muted) at baseline. Tile numbers are ~30pt so "mpg" fits inside the tile without clipping.

### Signature components (build once, reuse)
1. **OdometerView** (LCD): the same look for every car. Amber (#FFB000) mono digits with tight spacing, faint "888888" ghost behind in lcdGhost, small "MI" label. Sizes: 24pt in headers, 28 to 32pt in forms. Do not use per-car odometer styles.
2. **ReadoutTile**: panel with 16pt corner radius, 12pt padding, 92pt tall (80pt in compact rows), small caps label top-left, mono number bottom-left with unit. A highlighted variant has a 1.5pt accent border and an accent-colored number.
3. **BigActionButton**: full width, 56 to 60pt tall, 16pt radius, control colors, 26 to 30pt SF Symbol or custom icon, 16pt semibold label with letter-spacing about 2. Used for LOG FILL-UP and LOG SERVICE.
4. **PrimaryButton**: full width, 60pt, accent fill, #07080A text, letter-spacing about 2. Used only for Save/Import at the bottom of forms.
5. **CarChip**: 12pt rounded square (3 to 4pt radius) filled with the car's color. Precedes the car name everywhere.
6. **StatusLine**: icon plus text, never color alone. Amber with a clock icon for due soon; red with a warning triangle for overdue.
7. **CountPill**: small red pill (#2A1210 fill, red text, mono) with a warning-triangle icon and a number, placed right of the car name. Never above the fill button.
8. **PanelList**: one rounded panel (18pt radius) containing rows separated by divider lines, 12pt vertical row padding, 16pt horizontal.
9. **Chip row**: horizontally scrolling 36pt-tall capsule chips; selected = accent border + selected fill.

Hit targets are at least 44pt everywhere (the fill-up icon button on home is 68pt).

---

## 2. Navigation and information architecture

Current structure stays: Home (vehicle list) → Vehicle detail with tabs **Fuel | Maintenance | Stats** → forms. Changes:

- **Fuel is the default tab** in vehicle detail. (The auto city/highway MPG is the app's headline feature.)
- **Fill-up entry points differ on purpose:**
  - From **Home** (big fill button on a car card, and the existing swipe-right on a car): open straight into the **pump scanner**. On a successful scan, push the fill-up form with gallons and total filled and the odometer field focused. The scanner has an "Enter manually" fallback.
  - From the car's **Fuel tab** (LOG FILL-UP button): open the **manual form** with a visible SCAN PUMP button at the top.
- "Needs attention" stays on Home under the cars. Overdue items are never auto-hidden or collapsed.
- Debug sections ("Trips (testing)") stay reachable but out of the way (see Stats).

---

## 3. Screens

### 3.1 Home (board C1a)
- Flat #07080A. Title area minimal.
- **Car cards**, three in the mockup, each about 108pt tall, one per vehicle, same layout for all:
  - Left: 84pt **MPG gauge**: a 270° style arc with tick marks; the value arc is stroked with the accent; the number below or inside in mono with tight decimal ("26.6"). Build with SwiftUI `Path`/`Shape`, not an image. If a car has no MPG yet, draw the empty gauge track with no value arc and show a dash, not a made-up number.
  - Middle: **CarChip + name** (uppercase, letter-spacing about 2, 17 to 18pt semibold), then the **CountPill** if it has due or overdue items, then the model line (muted, 13pt), then the **OdometerView**.
  - Right: **68×68 icon-only fill-up button** (36pt pump icon, control colors), vertically centered in the card. No text label. (Labeled variants "FILL-UP" and "LOG / FILL-UP" were tried and rejected.) It opens the pump scanner.
- **Remove the duplicate "Next: ..." line** from each car row.
- **"SERVICE LAMPS" / Needs attention list** below the cars, sorted most overdue first. Row shows: service name, car (with chip), last done, due date or mileage, and the overdue or remaining amount via StatusLine (for example "6 yr overdue" or "298 mi left"). Last-done is a new field to display, derived from the latest matching MaintenanceEntry; hide it if there is no prior entry.

### 3.2 Vehicle detail, Fuel tab (board D)
Top to bottom:
1. Nav row: back (44pt), spacer, Edit, more (…). All controlSmall.
2. Title block: CarChip, name (30pt, letter-spacing about 2), CountPill, model line, then OdometerView (24pt) with a 44pt pencil button to edit the odometer.
3. Segmented tabs (3, 40pt tall each, in a panel with 4pt padding): selected tab uses the "selected" fill/border.
4. **Three MPG tiles** (equal columns, 10pt gap): CITY, HIGHWAY, COMBINED. Combined has the accent border and accent number. Each number is ~30pt mono with a small "mpg" beside it. If a value does not exist yet, show "--" with the unit, not a number.
5. Caption under the tiles (11.5pt muted): "Rough estimate · N tanks tracked so far". Show it until 3+ tanks with different city/highway mixes exist. There is **no** "Miles per gallon" heading.
6. **CURRENT TANK**: header row with title and "16.6 mi recorded · 18% highway" (sample numbers), then an 8pt rounded bar split city (neutral #5B6676) and highway (accent).
7. **LOG FILL-UP** BigActionButton (60pt, pump icon). Opens the manual form (see 3.5).
8. **FILL-UPS** list in a PanelList, newest first. Each row: date (15pt semibold), "gal · $ · $/gal" and odometer on two muted lines; right side MPG in mono at 26pt with small "mpg" under which the miles for that tank. Partial fills show "partial fill, not used for MPG" instead of MPG. Section header shows "Avg N · Last tank N mpg" in muted.

### 3.3 Vehicle detail, Maintenance tab (board E)
1. Same header and tabs, Maintenance selected.
2. **LOG SERVICE** BigActionButton (56pt, wrench icon).
3. **Search** field (48pt, magnifier, placeholder "Search services, parts, notes") plus a 48pt **filter** button.
4. **Chip row** of service types: "All" selected by default, then the types this car actually has (built from data, not a fixed list).
5. **PanelList** of service records, newest first. Row: service type (15pt semibold); "date · odometer"; parts line (muted); cost right-aligned in mono.
6. The **latest record of each service type** carries a StatusLine below: amber "Next 56,798 mi · 298 mi left" or red "Next Aug 2020 · 6 yr overdue". Older records of the same type have no status line.

### 3.4 Vehicle detail, Stats tab (board F)
1. Same header and tabs, Stats selected.
2. **Top tile row** (3 ReadoutTiles, 92pt): ALL-TIME mpg, RECENT mpg (accent-highlighted), COST / MI. These replace nothing on the existing screen; they are the "summary numbers".
3. **Reserved space for City and Highway MPG.** Colin wants these shown at the top of this screen once the trips feature is finished. Not mocked up. When adding them, extend the tile row using the same ReadoutTile style (for example a second row of two tiles, or a horizontally scrolling row); do not redesign the screen.
4. **MPG PER FILL-UP** chart (Swift Charts): `LineMark` + small `PointMark` in the accent; dashed `RuleMark` for the average with an "AVG" label; the latest point emphasized (larger, surface ring) with its value labeled; faint horizontal grid only; range chips 6M / 1Y / ALL (ALL default). Add a hover/drag selection readout in the app. Show an empty state ("Log a few more tanks to see a trend") until about 3 tanks exist.
5. **FUEL SPEND** panel: THIS YEAR and ALL-TIME totals in mono, with monthly bars for the last six months (current month in accent, others neutral #5B6676), each bar labeled with its dollar value and month.
6. **Trips (testing)**: keep the debug section, collapsed into a dashed-border row at the bottom, Debug builds only. Do not delete.

### 3.5 Fill-up flow (boards G, H, I)
**Pump scanner (G)** — opened from Home.
- Full-screen camera (VisionKit pump scanning already built). Top bar: close (44pt), car chip + name capsule, flashlight toggle (44pt).
- Corner brackets (off-white, 36pt arms) frame the scan area. When the scanner recognizes values, draw accent-colored boxes labeled TOTAL, GALLONS, PRICE / GAL over them.
- One line of text under the frame: "Point at the pump display" (16pt semibold). **No other helper text.**
- Bottom: ENTER MANUALLY BigActionButton. The mockup's camera area is a placeholder illustration; use the live feed.

**Fill-up form, manual (H)** — opened from the Fuel tab.
Top to bottom: Cancel (left) and "LOG FILL-UP" title with CarChip; SCAN PUMP BigActionButton (56pt, scan icon); then fields:
- **ODOMETER** panel with the OdometerView at 32pt, accent border (focused). **Never pre-filled.** Colin always enters what the dash shows at that moment. No helper text under it. Label is just "ODOMETER", with "MI" on the right.
- **GALLONS** and **TOTAL COST** tiles side by side (92pt, mono 30pt). Price per gallon is derived and shown in a muted caption underneath; it is computed from gallons and total, not typed.
- A PanelList with rows: **DATE** (default now), **FULL TANK** toggle (default on, subtitle "Turn off for a partial fill"), and **STATION, NOTES** (optional, expands).
- **SAVE FILL-UP** PrimaryButton pinned at the bottom (34pt bottom margin). The iOS keyboard will cover the lower part: make the form scroll and keep Save reachable (for example a keyboard toolbar or sticky bar).

**Fill-up form after scan (I)** — same layout, but: replace SCAN PUMP with a "Scanned from pump" banner (56pt, green check, **Rescan** button); gallons and total are prefilled from the scan; the odometer is empty with the cursor in it. Show derived $/gal as in H. Colin did not want a "to see this tank's MPG" hint under the odometer.

### 3.6 Service form (board J)
Cancel + "LOG SERVICE" title with CarChip. Then:
- **SERVICE**: chip row (Oil change, Tire rotation, Brake fluid, Air filter, Transmission fluid, Custom…). Use the car's/app's real service types; "Custom…" lets the user type one.
- **ODOMETER** panel (OdometerView 24pt, accent border). Empty on a new entry, manual only.
- **DATE** (default today) and **TOTAL COST** tiles side by side. Total cost sums the parts list; if the user types a total, that overrides.
- **PARTS USED**: PanelList of repeatable rows (part name, optional note such as "5 qt", cost in mono, remove button) plus an accent "Add part" row.
- **NEXT DUE**: "EVERY __ mi" and "OR EVERY __ months" (either or both). Show the computed result in amber with a clock icon: "Next at 61,500 mi or Oct 2027, whichever first". Computed from the entered odometer and date; show nothing if neither interval is filled.
- **NOTES** (optional row), then **SAVE SERVICE** PrimaryButton at the bottom. Same keyboard handling as the fill-up form.

### 3.7 Vehicle form (board K)
Used for Add and Edit (title "ADD VEHICLE" / "EDIT VEHICLE"). Cancel; header preview (CarChip, name 26pt, model line, updates live); fields in 14pt-radius panels (60pt tall, small caps label + 17pt value): NICKNAME, YEAR / MAKE / MODEL in one row, VIN (optional, mono); ODOMETER (OdometerView 28pt); **COLOR**: row of 36pt rounded-square swatches (selected has an off-white ring) with a "+" for custom (system ColorPicker), plus an optional COLOR NAME field ("Redondo Red Pearl" for the Acura); a collapsed **TRIP DETECTION** row (optional, chevron) reserved for the audio connection name used to auto-assign trips (contents not designed); **SAVE VEHICLE** PrimaryButton.

### 3.8 CSV import preview (board L)
Shown after the user picks a file, before anything is saved.
- File card: icon, file name, "N rows found", Change button.
- Three ReadoutTiles (80pt): NEW (accent highlight), SKIPPED, PROBLEMS (red number).
- **IMPORT INTO** row: vehicle picker (CarChip + name + chevron).
- Chip row: All / New / Skipped / Problems, each with a count.
- PanelList of parsed rows: fuel or wrench icon, "date · type", a detail line, and a badge: **NEW** (outlined), **SKIP** (muted, row dimmed, "Already in the app"), **FIX** (red, detail line in red, for example "Odometer 56,100 is lower than the one before").
- Footer text: "Skipped rows and problem rows are left out. Nothing is changed in your file." Then **IMPORT N RECORDS** PrimaryButton with the real count.
- Not designed yet: what tapping a FIX row does. Suggested: open the matching fill-up or service form prefilled so the user can correct it, or offer Skip.
- The columns and values shown are placeholders. Use the real format in `docs/csv-format.md`.

---

## 4. Data model changes
- `Vehicle.colorHex: String?` (default nil; show a neutral chip if nil).
- `Vehicle.colorName: String?` (optional text).
- Optional later: the audio-connection name on Vehicle (or wherever the trips feature stores it) for the Trip Detection row.
- All other fields already exist. Keep CloudKit constraints: defaults or optionals everywhere, no unique attributes, optional relationships.
- "Last done" on due items and "status line" on maintenance rows are derived from existing `MaintenanceEntry` data, not new fields.

---

## 5. Efficiency changes (summary)
1. Home → scanner is one tap (or one swipe); scan result lands you in the form with only the odometer left to type.
2. The odometer is the only field the user must type after a scan; it is never prefilled.
3. $/gal is derived, not entered. Total cost on services sums from parts.
4. Fuel is the default tab; the three MPG tiles are the first thing seen.
5. Maintenance search and type chips find records without leaving the tab.
6. Next-due is entered as intervals, and the app shows the computed result immediately.

## 6. Remove or hide
- Remove the duplicate "Next: ..." line from home car rows.
- Remove any "Miles per gallon" heading above the MPG tiles.
- No labels on the home fill-up button (icon only).
- No helper text under the odometer fields or on the scanner beyond "Point at the pump display".
- Debug "Trips (testing)" stays Debug-only, collapsed.
- Do not auto-hide or collapse overdue items.
- Old exploratory looks (paper light, paper night, red-lit cluster) are NOT to be implemented. They remain on the canvas only for reference.

## 7. Priorities (suggested order)
1. Design tokens, fonts, MonoNumber, OdometerView, ReadoutTile, button and chip components. Everything else depends on these.
2. Home screen (cards, gauge, service lamps, scanner entry).
3. Vehicle detail shell and Fuel tab.
4. Fill-up scanner and forms, with the two entry-point behaviors and the never-prefilled odometer.
5. Maintenance tab and service form.
6. Stats tab (summary tiles, trend chart, spend).
7. Vehicle form with color (`colorHex`).
8. CSV import preview.
9. Accessibility pass: Dynamic Type, VoiceOver labels on icon-only buttons (the fill button, back, more, pencil, flashlight), light-mode palette, contrast check on muted text, status lines never color-only.
10. Later: City/Highway tiles on Stats, Trip Detection row contents, FIX row behavior in CSV import.

## 8. Real data vs. sample data in the mockups
**Real:** the cars (Acura 2003 RSX daily driver, 1970 VW Bus project car, Mom's 2019 Lexus ES 300h) and the Acura's October 1 and October 10, 2026 fill-ups (27.4 and 26.6 mpg, the gallon and cost figures shown on those rows).

**Sample / placeholder (never ship these):** City 24.3 and Highway 31.5 MPG; "2 tanks tracked"; the 16.6 mi / 18% highway tank bar; last-done dates and overdue amounts on the home list; all Maintenance tab costs, parts, and older service dates and mileages; the Stats trend points, cost per mile, and every spend figure; Bus and Mom's Car colors; the 9.412 gal / $58.91 scanned fill-up; the pump-display numbers; the service-form values; all CSV counts and rows; and the sample odometer values.

## 9. Open questions for Colin
- Exact color for each car beyond the Acura's approximate Redondo Red Pearl, and whether to eventually use a car photo.
- What the FIX row does in CSV import.
- Layout of City/Highway tiles on Stats once trips is done.
- Contents of the Trip Detection row in the vehicle form.
