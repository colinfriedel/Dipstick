# Dipstick: light mode spec (addendum to Dipstick_Design_Spec.md)

Implement a light palette with the same roles as the dark one, and follow the system appearance (`colorScheme`). The dark palette in the main spec is unchanged. Define each color as an adaptive token (asset catalog color set or `Color` with light/dark variants), not hard-coded hex in views.

## Light color tokens
| Token | Dark | Light |
|---|---|---|
| ground (screen bg) | #07080A | #F2F3F5 |
| panel (cards, lists, inputs) | #101216 | #FFFFFF |
| panelBorder | #23272E | #D9DDE3 |
| divider (row separators) | #1C2026 | #ECEEF1 |
| control fill (big action buttons) | #171A1F | #FFFFFF |
| control border (big action buttons, 1.5pt) | #4A5260 | #AEB6C2 |
| controlSmall border (back/Edit/more) | #2A2F37 | #CBD1D9 |
| selected fill (tab, chip) | #1E232B | #E6EAF0 |
| selected border | #343B46 | #BFC7D2 |
| text | #DCE6F2 | #14181F |
| muted | #8A94A3 | #5A6472 |
| faint (placeholders, neutral chart bars) | #5B6676 | #8A94A3 |
| gauge tick marks | #3A414B | #C3CAD4 |
| gauge empty value / "--" text | #6B7482 | #8A94A3 |
| red (text, icons, overdue) | #FF5A4A | #D63A2B |
| red pill / FIX badge fill | #2A1210 | #FDE8E5 |
| red pill / FIX badge border | #5A2420 | #F0B8B1 |
| amber for STATUS TEXT and icons (due soon) | #FFB000 | #B26A00 |
| accent | #FF6A2B | #FF6A2B (unchanged) |

Car chip colors (colorHex) are the same in both modes.

## Odometer in light mode (important)
The OdometerView stays a **dark LCD window** in both modes. In light mode it is a rounded rectangle with background #14181F, corner radius 8, padding 5pt vertical and 9pt horizontal, containing the same amber digits (#FFB000, not the darker status amber) with the faint ghost "888888" (#2A2108) behind them. In dark mode it has no background rectangle. Do not use dark amber digits directly on a light panel.

## Everything else is unchanged
Layout, sizes, fonts, MonoNumber rules, component structure, and screen behavior are identical to the main spec. Only the colors above change. Charts: the line, points, and AVG rule keep the accent; the grid uses divider; the neutral bars use faint; the point ring uses the panel color.

## Notes
- The accent (#FF6A2B) is used for large numbers (30pt tile numbers), borders, buttons, and chart lines, which read fine on white. Do not use the accent for small body text in light mode; use text or muted instead.
- PrimaryButton (accent fill) keeps dark text (#07080A) in both modes.
- The pump scanner stays dark in both modes because it sits over the camera feed.

## Mockups
Light boards on the design canvas: M (Home), N (Fuel tab), O (Maintenance tab), P (Stats tab). These are the reference for the light look.

## Not yet mocked in light
Fill-up forms (manual and after-scan), service form, vehicle form, and CSV import preview. Build them with the tokens above; they should follow the same pattern (white panels on the #F2F3F5 ground, dark LCD odometer window in the odometer field).
