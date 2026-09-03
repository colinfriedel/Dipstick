package service

import (
	"testing"
	"time"

	"github.com/colinfriedel/dipstick/activity-service/models"
)

func ptr[T any](v T) *T { return &v }

func date(year, month, day int) models.Date {
	return models.Date{Year: year, Month: time.Month(month), Day: day}
}

func mEntry(serviceType string, odometer int, d models.Date, nextOdo *int, nextDate models.Date) models.MaintenanceEntry {
	return models.MaintenanceEntry{
		ServiceType:     serviceType,
		Odometer:        odometer,
		Date:            d,
		NextDueOdometer: nextOdo,
		NextDueDate:     nextDate,
	}
}

var today = date(2024, 6, 1)

func TestEvaluateDue(t *testing.T) {
	cfg := DefaultDueConfig() // 500 miles, 14 days

	tests := []struct {
		name       string
		currentOdo *int
		entry      models.MaintenanceEntry
		wantOK     bool
		wantStatus models.DueStatus
		wantMiles  *int
		wantDays   *int
	}{
		{
			name:       "no targets: excluded",
			currentOdo: ptr(50000),
			entry:      mEntry("oil change", 45000, date(2024, 1, 1), nil, models.Date{}),
			wantOK:     false,
		},
		{
			name:       "mileage far in the future: excluded",
			currentOdo: ptr(50000),
			entry:      mEntry("oil change", 45000, date(2024, 1, 1), ptr(60000), models.Date{}),
			wantOK:     false,
		},
		{
			name:       "mileage due soon",
			currentOdo: ptr(50000),
			entry:      mEntry("oil change", 45000, date(2024, 1, 1), ptr(50300), models.Date{}),
			wantOK:     true,
			wantStatus: models.DueSoon,
			wantMiles:  ptr(300),
		},
		{
			name:       "mileage exactly at the buffer edge is due soon",
			currentOdo: ptr(50000),
			entry:      mEntry("oil change", 45000, date(2024, 1, 1), ptr(50500), models.Date{}),
			wantOK:     true,
			wantStatus: models.DueSoon,
			wantMiles:  ptr(500),
		},
		{
			name:       "mileage overdue",
			currentOdo: ptr(50000),
			entry:      mEntry("oil change", 45000, date(2024, 1, 1), ptr(49000), models.Date{}),
			wantOK:     true,
			wantStatus: models.Overdue,
			wantMiles:  ptr(-1000),
		},
		{
			name:       "mileage target but current odometer unknown: excluded",
			currentOdo: nil,
			entry:      mEntry("oil change", 45000, date(2024, 1, 1), ptr(49000), models.Date{}),
			wantOK:     false,
		},
		{
			name:       "date due soon",
			currentOdo: ptr(50000),
			entry:      mEntry("registration", 0, date(2023, 6, 10), nil, date(2024, 6, 10)),
			wantOK:     true,
			wantStatus: models.DueSoon,
			wantDays:   ptr(9),
		},
		{
			name:       "date overdue",
			currentOdo: ptr(50000),
			entry:      mEntry("registration", 0, date(2023, 5, 1), nil, date(2024, 5, 1)),
			wantOK:     true,
			wantStatus: models.Overdue,
			wantDays:   ptr(-31),
		},
		{
			name:       "date far in the future: excluded",
			currentOdo: ptr(50000),
			entry:      mEntry("registration", 0, date(2023, 12, 1), nil, date(2024, 12, 1)),
			wantOK:     false,
		},
		{
			name:       "both targets: mileage fine, date overdue -> overdue",
			currentOdo: ptr(50000),
			entry:      mEntry("inspection", 45000, date(2023, 5, 1), ptr(60000), date(2024, 5, 1)),
			wantOK:     true,
			wantStatus: models.Overdue,
			wantMiles:  ptr(10000),
			wantDays:   ptr(-31),
		},
		{
			name:       "both targets: mileage due soon, date fine -> due soon",
			currentOdo: ptr(50000),
			entry:      mEntry("inspection", 45000, date(2024, 1, 1), ptr(50200), date(2025, 1, 1)),
			wantOK:     true,
			wantStatus: models.DueSoon,
			wantMiles:  ptr(200),
			wantDays:   ptr(today.DaysUntil(date(2025, 1, 1))),
		},
		{
			name:       "odometer unknown but a date target still evaluates",
			currentOdo: nil,
			entry:      mEntry("inspection", 45000, date(2023, 5, 1), ptr(60000), date(2024, 5, 1)),
			wantOK:     true,
			wantStatus: models.Overdue,
			wantDays:   ptr(-31),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := evaluateDue(1, tc.currentOdo, tc.entry, today, cfg)
			if ok != tc.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tc.wantOK)
			}
			if !tc.wantOK {
				return
			}
			if got.Status != tc.wantStatus {
				t.Errorf("status = %q, want %q", got.Status, tc.wantStatus)
			}
			assertIntPtr(t, "milesRemaining", got.MilesRemaining, tc.wantMiles)
			assertIntPtr(t, "daysRemaining", got.DaysRemaining, tc.wantDays)
		})
	}
}

func TestCalculateDue_SortsMostUrgentFirst(t *testing.T) {
	cfg := DefaultDueConfig()

	vehicles := []VehicleMaintenance{
		{
			VehicleID:       1,
			CurrentOdometer: ptr(50000),
			LatestByService: []models.MaintenanceEntry{
				mEntry("oil change", 45000, date(2024, 1, 1), ptr(50400), models.Date{}),    // due soon, +400 mi
				mEntry("tire rotation", 40000, date(2024, 1, 1), ptr(48000), models.Date{}), // overdue, -2000 mi
			},
		},
		{
			VehicleID:       2,
			CurrentOdometer: ptr(30000),
			LatestByService: []models.MaintenanceEntry{
				mEntry("brake pads", 20000, date(2024, 1, 1), ptr(30100), models.Date{}), // due soon, +100 mi
			},
		},
	}

	items := CalculateDue(vehicles, today, cfg)

	if len(items) != 3 {
		t.Fatalf("got %d items, want 3: %+v", len(items), items)
	}

	// Expected order: tire rotation (overdue) -> brake pads (+100) -> oil change (+400)
	want := []struct {
		vehicleID   int64
		serviceType string
		status      models.DueStatus
	}{
		{1, "tire rotation", models.Overdue},
		{2, "brake pads", models.DueSoon},
		{1, "oil change", models.DueSoon},
	}
	for i, w := range want {
		got := items[i]
		if got.VehicleID != w.vehicleID || got.ServiceType != w.serviceType || got.Status != w.status {
			t.Errorf("item %d = (v%d %q %s), want (v%d %q %s)",
				i, got.VehicleID, got.ServiceType, got.Status,
				w.vehicleID, w.serviceType, w.status)
		}
	}
}

func TestCalculateDue_Empty(t *testing.T) {
	if got := CalculateDue(nil, today, DefaultDueConfig()); len(got) != 0 {
		t.Fatalf("want no items, got %+v", got)
	}
}

func assertIntPtr(t *testing.T, name string, got, want *int) {
	t.Helper()
	switch {
	case got == nil && want == nil:
	case got == nil:
		t.Errorf("%s: got nil, want %d", name, *want)
	case want == nil:
		t.Errorf("%s: got %d, want nil", name, *got)
	case *got != *want:
		t.Errorf("%s: got %d, want %d", name, *got, *want)
	}
}
