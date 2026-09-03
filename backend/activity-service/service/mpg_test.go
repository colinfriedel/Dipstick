package service

import (
	"math"
	"testing"

	"github.com/colinfriedel/dipstick/activity-service/models"
)

// entry is a compact constructor for test fuel entries. Only the fields MPG math
// cares about are parameters; date defaults to a fixed day unless overridden.
func entry(id int64, odometer int, gallons float64, fullTank bool) models.FuelEntry {
	return models.FuelEntry{
		ID:         id,
		Odometer:   odometer,
		Gallons:    gallons,
		IsFullTank: fullTank,
		Date:       models.Date{Year: 2024, Month: 1, Day: 1},
	}
}

func TestCalculateMPG(t *testing.T) {
	const epsilon = 1e-9

	tests := []struct {
		name    string
		entries []models.FuelEntry
		want    map[int64]float64
	}{
		{
			name:    "no entries",
			entries: nil,
			want:    map[int64]float64{},
		},
		{
			name:    "single full tank has nothing to measure from",
			entries: []models.FuelEntry{entry(1, 1000, 10, true)},
			want:    map[int64]float64{},
		},
		{
			name: "two consecutive full tanks",
			entries: []models.FuelEntry{
				entry(1, 1000, 10, true),
				entry(2, 1300, 10, true),
			},
			// 300 miles / 10 gal (the closing tank's gallons)
			want: map[int64]float64{2: 30},
		},
		{
			name: "full, partial, full: partial gallons count toward the interval",
			entries: []models.FuelEntry{
				entry(1, 1000, 10, true),
				entry(2, 1150, 5, false),
				entry(3, 1300, 8, true),
			},
			// 300 miles / (5 partial + 8 closing) = 300 / 13
			want: map[int64]float64{3: 300.0 / 13.0},
		},
		{
			name: "all partial fill-ups: never calculable",
			entries: []models.FuelEntry{
				entry(1, 1000, 5, false),
				entry(2, 1100, 5, false),
				entry(3, 1200, 5, false),
			},
			want: map[int64]float64{},
		},
		{
			name: "partials before the first full tank are dropped",
			entries: []models.FuelEntry{
				entry(1, 900, 3, false),
				entry(2, 1000, 10, true),
				entry(3, 1300, 12, true),
			},
			want: map[int64]float64{3: 300.0 / 12.0},
		},
		{
			name: "three full tanks yield two intervals",
			entries: []models.FuelEntry{
				entry(1, 1000, 10, true),
				entry(2, 1300, 10, true),
				entry(3, 1600, 12, true),
			},
			want: map[int64]float64{2: 30, 3: 25},
		},
		{
			name: "unsorted input is handled",
			entries: []models.FuelEntry{
				entry(3, 1600, 12, true),
				entry(1, 1000, 10, true),
				entry(2, 1300, 10, true),
			},
			want: map[int64]float64{2: 30, 3: 25},
		},
		{
			name: "zero miles between full tanks: no value, window still resets",
			entries: []models.FuelEntry{
				entry(1, 1000, 10, true),
				entry(2, 1000, 4, true), // same odometer (bad data / immediate top-off)
				entry(3, 1250, 10, true),
			},
			// entry 2 skipped; entry 3 measured from entry 2's odometer:
			// 250 miles / 10 gal
			want: map[int64]float64{3: 25},
		},
		{
			name: "trailing partial after the last full tank does not panic",
			entries: []models.FuelEntry{
				entry(1, 1000, 10, true),
				entry(2, 1300, 10, true),
				entry(3, 1400, 4, false),
			},
			want: map[int64]float64{2: 30},
		},
		{
			name: "closing full tank with zero gallons and no partials is skipped",
			entries: []models.FuelEntry{
				entry(1, 1000, 10, true),
				entry(2, 1300, 0, true),
			},
			want: map[int64]float64{},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := CalculateMPG(tc.entries)

			if len(got) != len(tc.want) {
				t.Fatalf("got %d results %v, want %d %v", len(got), got, len(tc.want), tc.want)
			}
			for id, wantMPG := range tc.want {
				gotMPG, ok := got[id]
				if !ok {
					t.Errorf("entry %d: missing from results, want %.4f", id, wantMPG)
					continue
				}
				if math.Abs(gotMPG-wantMPG) > epsilon {
					t.Errorf("entry %d: got MPG %.6f, want %.6f", id, gotMPG, wantMPG)
				}
			}
		})
	}
}

// TestCalculateMPG_DoesNotMutateInput guards the "work on a copy" promise.
func TestCalculateMPG_DoesNotMutateInput(t *testing.T) {
	entries := []models.FuelEntry{
		entry(3, 1600, 12, true),
		entry(1, 1000, 10, true),
		entry(2, 1300, 10, true),
	}
	CalculateMPG(entries)

	if entries[0].ID != 3 || entries[1].ID != 1 || entries[2].ID != 2 {
		t.Fatalf("input slice was reordered: got IDs %d, %d, %d",
			entries[0].ID, entries[1].ID, entries[2].ID)
	}
}
