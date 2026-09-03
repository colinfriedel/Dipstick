package store

import (
	"context"

	"github.com/colinfriedel/dipstick/activity-service/models"
)

// rowScanner is the method shared by *sql.Row and *sql.Rows.
type rowScanner interface {
	Scan(dest ...any) error
}

// fuelColumns is the SELECT/RETURNING column list, in the exact order
// scanFuelEntry reads them.
//
// gallons and total_cost are stored as NUMERIC (exact decimal). We cast them to
// double precision here so they scan cleanly into Go float64 fields. For a
// personal fuel log this is fine — the rounding error is far below a cent, and
// MPG is a float anyway. Real money handling would keep NUMERIC end-to-end
// (e.g. a decimal type, or integer cents).
const fuelColumns = `
	id,
	vehicle_id,
	date,
	odometer,
	gallons::double precision,
	total_cost::double precision,
	is_full_tank,
	station_name,
	notes`

func scanFuelEntry(s rowScanner) (models.FuelEntry, error) {
	var e models.FuelEntry
	err := s.Scan(
		&e.ID,
		&e.VehicleID,
		&e.Date,
		&e.Odometer,
		&e.Gallons,
		&e.TotalCost,
		&e.IsFullTank,
		&e.StationName,
		&e.Notes,
	)
	return e, err
}

// ListFuelEntries returns every fuel entry for one vehicle, newest first (that's
// the order the fuel history screen wants). MPG math re-sorts by odometer on its
// own, so this display order is independent of it.
func (s *Store) ListFuelEntries(ctx context.Context, vehicleID int64) ([]models.FuelEntry, error) {
	const query = `
		SELECT ` + fuelColumns + `
		FROM activity.fuel_entries
		WHERE vehicle_id = $1
		ORDER BY date DESC, odometer DESC, id DESC`

	rows, err := s.db.QueryContext(ctx, query, vehicleID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	entries := []models.FuelEntry{}
	for rows.Next() {
		e, err := scanFuelEntry(rows)
		if err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}

// CreateFuelEntry inserts a new fuel entry and returns it as stored.
//
// The caller (the HTTP handler) is responsible for validation and has already
// guaranteed that in.TotalCost and in.IsFullTank are non-nil.
func (s *Store) CreateFuelEntry(ctx context.Context, vehicleID int64, in models.FuelEntryInput) (models.FuelEntry, error) {
	const query = `
		INSERT INTO activity.fuel_entries
			(vehicle_id, date, odometer, gallons, total_cost, is_full_tank, station_name, notes)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING ` + fuelColumns

	return scanFuelEntry(s.db.QueryRowContext(ctx, query,
		vehicleID,
		in.Date,
		in.Odometer,
		in.Gallons,
		*in.TotalCost,
		*in.IsFullTank,
		in.StationName,
		in.Notes,
	))
}
