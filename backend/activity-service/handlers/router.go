package handlers

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/colinfriedel/dipstick/activity-service/client"
	"github.com/colinfriedel/dipstick/activity-service/models"
	"github.com/colinfriedel/dipstick/activity-service/service"
)

// FuelStore is the slice of the data layer the fuel handlers need.
type FuelStore interface {
	ListFuelEntries(ctx context.Context, vehicleID int64) ([]models.FuelEntry, error)
	CreateFuelEntry(ctx context.Context, vehicleID int64, in models.FuelEntryInput) (models.FuelEntry, error)
}

// MaintenanceStore is the slice the maintenance and due handlers need.
type MaintenanceStore interface {
	ListMaintenanceEntries(ctx context.Context, vehicleID int64) ([]models.MaintenanceEntry, error)
	CreateMaintenanceEntry(ctx context.Context, vehicleID int64, in models.MaintenanceEntryInput) (models.MaintenanceEntry, error)
	LatestMaintenancePerService(ctx context.Context) ([]models.MaintenanceEntry, error)
}

// VehicleAPI is activity-service's dependency on vehicle-service.
// *client.VehicleClient satisfies it.
type VehicleAPI interface {
	GetVehicle(ctx context.Context, id int64) (client.Vehicle, error)
	ListVehicles(ctx context.Context) ([]client.Vehicle, error)
}

// Deps bundles everything the router wires into handlers. Grouping them in a
// struct keeps NewRouter's signature stable as more handlers are added.
type Deps struct {
	Fuel        FuelStore
	Maintenance MaintenanceStore
	Vehicles    VehicleAPI
	DueConfig   service.DueConfig
}

// NewRouter wires every route to its handler.
func NewRouter(d Deps) http.Handler {
	mux := http.NewServeMux()

	fuel := &FuelHandler{store: d.Fuel, vehicles: d.Vehicles}
	maintenance := &MaintenanceHandler{store: d.Maintenance, vehicles: d.Vehicles}
	due := &DueHandler{store: d.Maintenance, vehicles: d.Vehicles, config: d.DueConfig}

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /vehicles/{id}/fuel-entries", fuel.List)
	mux.HandleFunc("POST /vehicles/{id}/fuel-entries", fuel.Create)

	mux.HandleFunc("GET /vehicles/{id}/maintenance-entries", maintenance.List)
	mux.HandleFunc("POST /vehicles/{id}/maintenance-entries", maintenance.Create)

	mux.HandleFunc("GET /due", due.List)

	return requestLogger(mux)
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(start))
	})
}
