package reconcile

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/colinfriedel/dipstick/activity-service/client"
)

type fakeStore struct {
	knownIDs []int64
	deleted  []int64
	delErr   error
}

func (f *fakeStore) DistinctActivityVehicleIDs(ctx context.Context) ([]int64, error) {
	return f.knownIDs, nil
}

func (f *fakeStore) DeleteActivityForVehicle(ctx context.Context, vehicleID int64) (int64, error) {
	if f.delErr != nil {
		return 0, f.delErr
	}
	f.deleted = append(f.deleted, vehicleID)
	return 3, nil
}

type fakeLister struct {
	vehicles []client.Vehicle
	err      error
}

func (f *fakeLister) ListVehicles(ctx context.Context) ([]client.Vehicle, error) {
	return f.vehicles, f.err
}

func run(store Store, lister VehicleLister) {
	New(store, lister, time.Hour).runOnce(context.Background())
}

func TestReconcile_DeletesOrphansOnly(t *testing.T) {
	store := &fakeStore{knownIDs: []int64{1, 2, 3}}
	lister := &fakeLister{vehicles: []client.Vehicle{{ID: 1}, {ID: 3}}} // 2 is gone

	run(store, lister)

	if len(store.deleted) != 1 || store.deleted[0] != 2 {
		t.Fatalf("deleted = %v, want [2]", store.deleted)
	}
}

func TestReconcile_NothingToDo(t *testing.T) {
	store := &fakeStore{knownIDs: []int64{1, 2}}
	lister := &fakeLister{vehicles: []client.Vehicle{{ID: 1}, {ID: 2}}}

	run(store, lister)

	if len(store.deleted) != 0 {
		t.Fatalf("deleted = %v, want none", store.deleted)
	}
}

func TestReconcile_SkipsWhenVehicleListEmpty(t *testing.T) {
	store := &fakeStore{knownIDs: []int64{1, 2, 3}}
	lister := &fakeLister{vehicles: nil} // empty!

	run(store, lister)

	if len(store.deleted) != 0 {
		t.Fatalf("deleted %v — must never mass-delete on an empty vehicle list", store.deleted)
	}
}

func TestReconcile_SkipsWhenVehicleServiceUnavailable(t *testing.T) {
	store := &fakeStore{knownIDs: []int64{1, 2, 3}}
	lister := &fakeLister{err: client.ErrVehicleServiceUnavailable}

	run(store, lister)

	if len(store.deleted) != 0 {
		t.Fatalf("deleted %v — must not delete when it can't confirm the live list", store.deleted)
	}
}

func TestReconcile_ContinuesPastADeleteError(t *testing.T) {
	store := &fakeStore{knownIDs: []int64{7, 8}, delErr: errors.New("db boom")}
	lister := &fakeLister{vehicles: []client.Vehicle{{ID: 99}}} // 7 and 8 are both orphans

	run(store, lister) // should not panic; errors are logged and swallowed
}
