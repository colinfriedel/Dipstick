package store

import "context"

// DistinctActivityVehicleIDs returns every vehicle_id that appears in either
// activity table. The orphan reconciler diffs this against vehicle-service's
// live list.
func (s *Store) DistinctActivityVehicleIDs(ctx context.Context) ([]int64, error) {
	const query = `
		SELECT vehicle_id FROM activity.fuel_entries
		UNION
		SELECT vehicle_id FROM activity.maintenance_entries`

	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// DeleteActivityForVehicle removes every fuel and maintenance row for one
// vehicle, and returns how many rows went.
//
// Both deletes run inside a single transaction: either all of that vehicle's
// activity data is gone or none of it is, never a half-deleted state.
//
// The `defer tx.Rollback()` is the standard idiom. If Commit succeeds, the
// deferred Rollback is a harmless no-op (it returns sql.ErrTxDone, which we
// ignore). If we return early with an error, the Rollback undoes the partial work.
func (s *Store) DeleteActivityForVehicle(ctx context.Context, vehicleID int64) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	fuelResult, err := tx.ExecContext(ctx,
		`DELETE FROM activity.fuel_entries WHERE vehicle_id = $1`, vehicleID)
	if err != nil {
		return 0, err
	}

	maintResult, err := tx.ExecContext(ctx,
		`DELETE FROM activity.maintenance_entries WHERE vehicle_id = $1`, vehicleID)
	if err != nil {
		return 0, err
	}

	if err := tx.Commit(); err != nil {
		return 0, err
	}

	fuelRows, _ := fuelResult.RowsAffected()
	maintRows, _ := maintResult.RowsAffected()
	return fuelRows + maintRows, nil
}
