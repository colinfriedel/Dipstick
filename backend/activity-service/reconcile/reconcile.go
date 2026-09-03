// Package reconcile contains the background job that keeps activity-service's
// data consistent with vehicle-service without either service calling the other
// on the delete path.
//
// Why a loop and not a synchronous "vehicle deleted" webhook: a webhook would
// make the two services depend on each other (vehicle-service would have to know
// about activity-service). This loop keeps the dependency one-directional —
// activity-service asks vehicle-service "who still exists?" and cleans up after
// itself. It's eventually consistent, which is fine: GET /due already filters
// out orphaned vehicles at query time, so this loop is about reclaiming storage,
// not correctness.
package reconcile

import (
	"context"
	"log"
	"time"

	"github.com/colinfriedel/dipstick/activity-service/client"
)

// Store is the slice of the data layer the reconciler needs.
type Store interface {
	DistinctActivityVehicleIDs(ctx context.Context) ([]int64, error)
	DeleteActivityForVehicle(ctx context.Context, vehicleID int64) (int64, error)
}

// VehicleLister is the reconciler's read of vehicle-service. It should be the
// *raw* client, not the caching one — this job makes delete decisions and wants
// ground truth.
type VehicleLister interface {
	ListVehicles(ctx context.Context) ([]client.Vehicle, error)
}

// Reconciler deletes activity rows for vehicles that vehicle-service no longer
// knows about.
type Reconciler struct {
	store    Store
	vehicles VehicleLister
	interval time.Duration
}

func New(store Store, vehicles VehicleLister, interval time.Duration) *Reconciler {
	return &Reconciler{store: store, vehicles: vehicles, interval: interval}
}

// Run executes one pass immediately, then once per interval until ctx is
// cancelled. It's meant to be launched in its own goroutine.
func (r *Reconciler) Run(ctx context.Context) {
	log.Printf("reconcile: starting, interval %s", r.interval)

	r.runOnce(ctx)

	ticker := time.NewTicker(r.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Println("reconcile: stopping")
			return
		case <-ticker.C:
			r.runOnce(ctx)
		}
	}
}

func (r *Reconciler) runOnce(ctx context.Context) {
	liveVehicles, err := r.vehicles.ListVehicles(ctx)
	if err != nil {
		log.Printf("reconcile: skipping this pass, could not list vehicles: %v", err)
		return
	}

	// Guard: an empty list almost always means something is wrong (a
	// misconfigured URL, vehicle-service returning nonsense), not that the user
	// genuinely has zero vehicles. Deleting every activity row on that basis
	// would be catastrophic, so we refuse.
	if len(liveVehicles) == 0 {
		log.Println("reconcile: vehicle list is empty, skipping (refusing to treat that as 'delete everything')")
		return
	}

	live := make(map[int64]bool, len(liveVehicles))
	for _, v := range liveVehicles {
		live[v.ID] = true
	}

	known, err := r.store.DistinctActivityVehicleIDs(ctx)
	if err != nil {
		log.Printf("reconcile: could not list activity vehicle ids: %v", err)
		return
	}

	for _, vehicleID := range known {
		if live[vehicleID] {
			continue
		}
		deleted, err := r.store.DeleteActivityForVehicle(ctx, vehicleID)
		if err != nil {
			log.Printf("reconcile: deleting activity for orphaned vehicle %d: %v", vehicleID, err)
			continue
		}
		log.Printf("reconcile: removed %d activity row(s) for orphaned vehicle %d", deleted, vehicleID)
	}
}
