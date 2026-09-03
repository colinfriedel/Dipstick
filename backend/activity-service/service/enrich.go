package service

import "github.com/colinfriedel/dipstick/activity-service/models"

// EnrichFuelEntries fills in the two derived fields on each entry in place:
// CostPerGallon and MPG. Handlers call this once after loading entries from the
// store, so the computation lives in one place rather than being sprinkled
// through the HTTP layer.
//
// The slice is expected to contain every entry for one vehicle — MPG needs the
// full history to find full-tank intervals, even though only some entries end up
// with a value.
func EnrichFuelEntries(entries []models.FuelEntry) {
	mpgByID := CalculateMPG(entries)

	for i := range entries {
		e := &entries[i]

		if e.Gallons > 0 {
			e.CostPerGallon = e.TotalCost / e.Gallons
		}

		if mpg, ok := mpgByID[e.ID]; ok {
			value := mpg // new variable per iteration so &value is distinct
			e.MPG = &value
		}
	}
}
