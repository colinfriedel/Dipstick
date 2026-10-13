# Dipstick CSV format

One CSV file holds one vehicle's fuel and service records. The app's Export
writes this format and Import reads it (into whichever vehicle you import from),
so an export is also a backup.

## Columns

First line is this header, exactly:

```
type,date,odometer,gallons,total_cost,full_tank,station,service,parts,next_due_odometer,next_due_date,notes
```

| Column | Used by | Format | Notes |
|---|---|---|---|
| `type` | both | `fuel` or `service` | Required. |
| `date` | both | `YYYY-MM-DD` | Required. |
| `odometer` | both | whole number, no commas (`55171`) | Required. If only trip miles are known, estimate from a nearby known reading. |
| `gallons` | fuel | decimal (`10.227`) | Required for fuel. Blank for service. |
| `total_cost` | both | decimal, no `$` (`61.35`) | Blank if unknown. For services: the full amount paid, parts + labor. |
| `full_tank` | fuel | `yes` or `no` | Fuel only; `no` = partial fill. Blank for service. |
| `station` | fuel | text | Optional. |
| `service` | service | text | Required for service. Use one of the standard names below when it fits; otherwise any name. |
| `parts` | service | `Name=cost; Name=cost` | Optional. Separate parts with `;`. Cost is optional (`Oil filter=9.99; Drain plug gasket`). |
| `next_due_odometer` | service | whole number | Optional. The odometer reading when this service is next due (not the interval). |
| `next_due_date` | service | `YYYY-MM-DD` | Optional. The date this service is next due. |
| `notes` | both | text | Optional. |

Standard service names: Oil change, Tire rotation, Brake pads, Air filter,
Cabin air filter, Spark plugs, Coolant, Transmission fluid, Brake fluid, Fluids,
Battery, Wiper blades, Inspection.

## Rules

- Standard CSV quoting: wrap a field in double quotes if it contains a comma,
  a double quote or a line break; write a double quote inside a field as `""`.
- Leave unused columns empty, but keep every comma (12 columns per row).
- One row per fill-up or per service. If one visit covered several services
  (e.g. oil change + tire rotation), use one row per service and split the cost
  sensibly (or put the whole bill on one row and 0 on the others).
- Due tracking uses only the most recent record of each service, so
  `next_due_*` matters most on the latest one. Leave it blank on a service you
  don't want reminders for.
- Rows can be in any order.

## Example

```
type,date,odometer,gallons,total_cost,full_tank,station,service,parts,next_due_odometer,next_due_date,notes
fuel,2026-08-31,55171,10.227,61.35,yes,,,,,,
fuel,2026-08-21,54586,10.808,63.78,yes,,,,,,"Gas light came on a mile from the gas station"
service,2026-09-02,55190,,48.50,,,Oil change,"Mobil 1 5W-30 5qt=32.50; Oil filter=9.99; Drain plug gasket=1.50",60190,2027-03-02,Did it myself
service,2026-09-02,55190,,,,,Tire rotation,,60190,,
```
