package store

import (
	"context"

	"github.com/colinfriedel/dipstick/activity-service/models"
)

// maintenanceColumns is the SELECT/RETURNING list, in the order
// scanMaintenanceEntry reads them. cost is cast to double precision for a clean
// float64 scan (same reasoning as fuelColumns).
const maintenanceColumns = `
	id,
	vehicle_id,
	date,
	odometer,
	service_type,
	cost::double precision,
	parts_used,
	notes,
	next_due_odometer,
	next_due_date`

func scanMaintenanceEntry(s rowScanner) (models.MaintenanceEntry, error) {
	var e models.MaintenanceEntry
	err := s.Scan(
		&e.ID,
		&e.VehicleID,
		&e.Date,
		&e.Odometer,
		&e.ServiceType,
		&e.Cost,
		&e.PartsUsed, // *models.Parts — sql.Scanner unmarshals the JSONB column
		&e.Notes,
		&e.NextDueOdometer, // **int — database/sql handles the nullable column
		&e.NextDueDate,     // *models.Date — Scan turns SQL NULL into the zero Date
	)
	return e, err
}

// ListMaintenanceEntries returns every maintenance entry for one vehicle, newest
// first.
func (s *Store) ListMaintenanceEntries(ctx context.Context, vehicleID int64) ([]models.MaintenanceEntry, error) {
	const query = `
		SELECT ` + maintenanceColumns + `
		FROM activity.maintenance_entries
		WHERE vehicle_id = $1
		ORDER BY date DESC, odometer DESC, id DESC`

	rows, err := s.db.QueryContext(ctx, query, vehicleID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	entries := []models.MaintenanceEntry{}
	for rows.Next() {
		e, err := scanMaintenanceEntry(rows)
		if err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}

// CreateMaintenanceEntry inserts a new entry and returns it as stored. The
// handler has already validated the input and guaranteed in.Cost is non-nil.
func (s *Store) CreateMaintenanceEntry(ctx context.Context, vehicleID int64, in models.MaintenanceEntryInput) (models.MaintenanceEntry, error) {
	const query = `
		INSERT INTO activity.maintenance_entries
			(vehicle_id, date, odometer, service_type, cost, parts_used, notes, next_due_odometer, next_due_date)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING ` + maintenanceColumns

	return scanMaintenanceEntry(s.db.QueryRowContext(ctx, query,
		vehicleID,
		in.Date,
		in.Odometer,
		in.ServiceType,
		*in.Cost,
		in.PartsUsed, // models.Parts — driver.Valuer marshals to JSONB (nil -> NULL)
		in.Notes,
		in.NextDueOdometer,
		in.NextDueDate, // models.Date — zero value -> SQL NULL
	))
}

// LatestMaintenancePerService returns, for every (vehicle, service_type) pair
// that has any maintenance entries, the single most recent one — across all
// vehicles, in one query. This is what the /due calculation walks.
//
// DISTINCT ON (a, b) is a Postgres feature: with an ORDER BY that starts with
// a, b, it keeps the first row of each (a, b) group. Continuing the ORDER BY
// with date DESC, odometer DESC makes "first" mean "most recent".
func (s *Store) LatestMaintenancePerService(ctx context.Context) ([]models.MaintenanceEntry, error) {
	const query = `
		SELECT DISTINCT ON (vehicle_id, service_type) ` + maintenanceColumns + `
		FROM activity.maintenance_entries
		ORDER BY vehicle_id, service_type, date DESC, odometer DESC, id DESC`

	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	entries := []models.MaintenanceEntry{}
	for rows.Next() {
		e, err := scanMaintenanceEntry(rows)
		if err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}
