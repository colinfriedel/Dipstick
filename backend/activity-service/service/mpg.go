// Package service holds activity-service's business logic — the rules that
// aren't HTTP handling and aren't SQL. Right now that's MPG calculation; the
// maintenance "due" logic joins it in Milestone 3.
package service

import (
	"sort"

	"github.com/colinfriedel/dipstick/activity-service/models"
)

// CalculateMPG computes miles-per-gallon for every fuel entry that closes an
// interval between two consecutive full-tank fill-ups, for a single vehicle.
//
// The rule (docs/Dipstick_Architecture.md section 4):
//
//	MPG = (thisFullTank.odometer - previousFullTank.odometer) / gallonsBurned
//
// where gallonsBurned = this full tank's gallons + every partial fill-up logged
// since the previous full tank. The previous full tank's own gallons are NOT
// counted: you started that interval with a full tank, so those gallons were
// burned in the interval that *ended* there.
//
// Returns a map from fuel-entry ID to MPG. An entry absent from the map has no
// calculable MPG — it's a partial fill-up, it's the first full tank (no earlier
// one to measure from), or the numbers don't yield a sane result (zero/negative
// miles, zero gallons).
//
// Algorithm: sort by odometer once (O(n log n)), then a single walk (O(n))
// carrying a running "gallons since the last full tank" total. No per-pair
// database queries, no nested loops.
func CalculateMPG(entries []models.FuelEntry) map[int64]float64 {
	// Work on a copy so we never reorder the caller's slice (it's displayed
	// newest-first elsewhere).
	sorted := make([]models.FuelEntry, len(entries))
	copy(sorted, entries)
	sort.Slice(sorted, func(i, j int) bool {
		a, b := sorted[i], sorted[j]
		if a.Odometer != b.Odometer {
			return a.Odometer < b.Odometer
		}
		if !a.Date.Equal(b.Date) {
			return a.Date.Before(b.Date)
		}
		return a.ID < b.ID // final tiebreak: stable, deterministic
	})

	result := make(map[int64]float64)

	// The "anchor" is the most recent full-tank fill-up we've seen; every
	// interval is measured from it.
	var haveAnchor bool
	var anchorOdometer int
	var gallonsSinceAnchor float64

	for _, e := range sorted {
		if !haveAnchor {
			// Nothing to measure from yet. A partial fill-up here can't be
			// attributed to any interval, so we just drop it. A full tank
			// becomes the first anchor.
			if e.IsFullTank {
				haveAnchor = true
				anchorOdometer = e.Odometer
				gallonsSinceAnchor = 0
			}
			continue
		}

		// Every fill-up after the anchor adds fuel that was burned in this
		// interval — partials included.
		gallonsSinceAnchor += e.Gallons

		if !e.IsFullTank {
			continue // a partial just extends the open interval
		}

		// A full tank closes the interval: compute, then re-anchor here.
		miles := e.Odometer - anchorOdometer
		if miles > 0 && gallonsSinceAnchor > 0 {
			result[e.ID] = float64(miles) / gallonsSinceAnchor
		}
		anchorOdometer = e.Odometer
		gallonsSinceAnchor = 0
	}

	return result
}
