package store

import (
	"context"
	"database/sql"
	"errors"

	"github.com/colinfriedel/dipstick/vehicle-service/models"
)

// rowScanner is the one method both *sql.Row and *sql.Rows share. Accepting it
// lets scanVehicle handle a single-row query and a loop over many rows with the
// same code.
type rowScanner interface {
	Scan(dest ...any) error
}

// scanVehicle reads one row's columns, in SELECT order, into a Vehicle.
//
// For the nullable columns we pass the address of a pointer field (e.g. **int).
// database/sql understands this: a SQL NULL leaves the pointer nil, a real value
// gets allocated and assigned.
func scanVehicle(s rowScanner) (models.Vehicle, error) {
	var v models.Vehicle
	err := s.Scan(
		&v.ID,
		&v.Name,
		&v.Year,
		&v.Make,
		&v.Model,
		&v.VIN,
		&v.CurrentOdometer,
	)
	return v, err
}

// columns lists the vehicle columns in a fixed order, reused by every query so
// the SELECT list and scanVehicle can never drift apart.
const columns = `id, name, year, make, model, vin, current_odometer`

// ListVehicles returns all vehicles, oldest first.
func (s *Store) ListVehicles(ctx context.Context) ([]models.Vehicle, error) {
	const query = `SELECT ` + columns + ` FROM vehicle.vehicles ORDER BY id`

	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Start from an empty (non-nil) slice so the JSON response is [] not null
	// when there are no vehicles.
	vehicles := []models.Vehicle{}
	for rows.Next() {
		v, err := scanVehicle(rows)
		if err != nil {
			return nil, err
		}
		vehicles = append(vehicles, v)
	}
	// rows.Next() returning false can mean "done" or "error" — rows.Err()
	// disambiguates.
	return vehicles, rows.Err()
}

// GetVehicle returns one vehicle by id, or ErrNotFound.
func (s *Store) GetVehicle(ctx context.Context, id int64) (models.Vehicle, error) {
	const query = `SELECT ` + columns + ` FROM vehicle.vehicles WHERE id = $1`

	v, err := scanVehicle(s.db.QueryRowContext(ctx, query, id))
	if errors.Is(err, sql.ErrNoRows) {
		return models.Vehicle{}, ErrNotFound
	}
	if err != nil {
		return models.Vehicle{}, err
	}
	return v, nil
}

// CreateVehicle inserts a new vehicle and returns it with its assigned id.
//
// RETURNING is a Postgres feature that hands back columns from the affected row
// in the same round trip — no separate SELECT needed. current_odometer has a
// DEFAULT in the schema, but we always send an explicit value (0 if the client
// omitted it), so the column list is stable.
func (s *Store) CreateVehicle(ctx context.Context, in models.VehicleInput) (models.Vehicle, error) {
	const query = `
		INSERT INTO vehicle.vehicles (name, year, make, model, vin, current_odometer)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING ` + columns

	return scanVehicle(s.db.QueryRowContext(ctx, query,
		in.Name, in.Year, in.Make, in.Model, in.VIN, in.CurrentOdometer,
	))
}

// UpdateVehicle overwrites every mutable column of an existing vehicle (PUT
// semantics — the client sends the full desired state). Returns ErrNotFound if
// no row has that id.
func (s *Store) UpdateVehicle(ctx context.Context, id int64, in models.VehicleInput) (models.Vehicle, error) {
	const query = `
		UPDATE vehicle.vehicles
		SET name = $1, year = $2, make = $3, model = $4, vin = $5, current_odometer = $6
		WHERE id = $7
		RETURNING ` + columns

	v, err := scanVehicle(s.db.QueryRowContext(ctx, query,
		in.Name, in.Year, in.Make, in.Model, in.VIN, in.CurrentOdometer, id,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return models.Vehicle{}, ErrNotFound
	}
	if err != nil {
		return models.Vehicle{}, err
	}
	return v, nil
}

// DeleteVehicle removes a vehicle. The fuel_entries / maintenance_entries tables
// (added in later milestones) use ON DELETE CASCADE, so their rows go with it.
func (s *Store) DeleteVehicle(ctx context.Context, id int64) error {
	const query = `DELETE FROM vehicle.vehicles WHERE id = $1`

	result, err := s.db.ExecContext(ctx, query, id)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return ErrNotFound
	}
	return nil
}
