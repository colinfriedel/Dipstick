package service

import (
	"math"
	"sort"

	"github.com/colinfriedel/dipstick/activity-service/models"
)

// DueConfig holds the two "how close counts as due soon" buffers. The spec calls
// these tunable; main.go can override the defaults from the environment.
type DueConfig struct {
	MilesBuffer int // e.g. 500: within 500 miles of the target is "due soon"
	DaysBuffer  int // e.g. 14: within 14 days of the target is "due soon"
}

// DefaultDueConfig is the buffer used when nothing overrides it.
func DefaultDueConfig() DueConfig {
	return DueConfig{MilesBuffer: 500, DaysBuffer: 14}
}

func (c DueConfig) normalized() DueConfig {
	if c.MilesBuffer < 1 {
		c.MilesBuffer = 1
	}
	if c.DaysBuffer < 1 {
		c.DaysBuffer = 1
	}
	return c
}

// VehicleMaintenance bundles one vehicle's current odometer with the most recent
// maintenance entry for each of its distinct service types.
//
// CurrentOdometer is a pointer: nil means vehicle-service didn't give us this
// vehicle's data (it was unreachable), so mileage-based checks are skipped for
// this vehicle and only date-based ones run.
type VehicleMaintenance struct {
	VehicleID       int64
	CurrentOdometer *int
	LatestByService []models.MaintenanceEntry
}

// CalculateDue returns every (vehicle, service type) that is due soon or overdue,
// most urgent first. Anything comfortably in the future — or with no next-due
// target at all — is left out.
//
// It's a straightforward double loop: vehicles × their service types. The result
// is sorted once. There's no cheaper structure here: you have to look at every
// service type to know whether it's due, so a heap would only add ceremony.
func CalculateDue(vehicles []VehicleMaintenance, today models.Date, cfg DueConfig) []models.DueItem {
	cfg = cfg.normalized()

	var items []models.DueItem
	for _, v := range vehicles {
		for _, entry := range v.LatestByService {
			if item, ok := evaluateDue(v.VehicleID, v.CurrentOdometer, entry, today, cfg); ok {
				items = append(items, item)
			}
		}
	}

	sort.Slice(items, func(i, j int) bool {
		ui, uj := urgency(items[i], cfg), urgency(items[j], cfg)
		if ui != uj {
			return ui < uj // lower (more negative) = more overdue = first
		}
		if items[i].VehicleID != items[j].VehicleID {
			return items[i].VehicleID < items[j].VehicleID
		}
		return items[i].ServiceType < items[j].ServiceType
	})

	return items
}

// evaluateDue scores one service type for one vehicle.
func evaluateDue(vehicleID int64, currentOdometer *int, entry models.MaintenanceEntry, today models.Date, cfg DueConfig) (models.DueItem, bool) {
	item := models.DueItem{
		VehicleID:           vehicleID,
		ServiceType:         entry.ServiceType,
		NextDueOdometer:     entry.NextDueOdometer,
		NextDueDate:         entry.NextDueDate,
		LastServiceOdometer: entry.Odometer,
		LastServiceDate:     entry.Date,
	}

	var overdue, dueSoon bool

	// Mileage dimension: needs both a target and a known current odometer.
	if entry.NextDueOdometer != nil && currentOdometer != nil {
		remaining := *entry.NextDueOdometer - *currentOdometer
		item.MilesRemaining = &remaining
		switch {
		case remaining <= 0:
			overdue = true
		case remaining <= cfg.MilesBuffer:
			dueSoon = true
		}
	}

	// Date dimension: needs only a target (today is always known).
	if !entry.NextDueDate.IsZero() {
		remaining := today.DaysUntil(entry.NextDueDate)
		item.DaysRemaining = &remaining
		switch {
		case remaining <= 0:
			overdue = true
		case remaining <= cfg.DaysBuffer:
			dueSoon = true
		}
	}

	switch {
	case overdue:
		item.Status = models.Overdue
	case dueSoon:
		item.Status = models.DueSoon
	default:
		return models.DueItem{}, false
	}
	return item, true
}

// urgency maps an item onto a single sortable number: remaining / buffer for
// whichever dimensions apply, taking the worst (smallest). <= 0 is overdue,
// (0, 1] is due soon.
func urgency(item models.DueItem, cfg DueConfig) float64 {
	score := math.Inf(1)
	if item.MilesRemaining != nil {
		score = math.Min(score, float64(*item.MilesRemaining)/float64(cfg.MilesBuffer))
	}
	if item.DaysRemaining != nil {
		score = math.Min(score, float64(*item.DaysRemaining)/float64(cfg.DaysBuffer))
	}
	return score
}
