package handlers

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/colinfriedel/dipstick/activity-service/client"
	"github.com/colinfriedel/dipstick/activity-service/models"
)

// FuelStore is the slice of the data layer the fuel handlers need. *store.Store
// satisfies it; tests pass a fake.
type FuelStore interface {
	ListFuelEntries(ctx context.Context, vehicleID int64) ([]models.FuelEntry, error)
	CreateFuelEntry(ctx context.Context, vehicleID int64, in models.FuelEntryInput) (models.FuelEntry, error)
}

// VehicleValidator is activity-service's dependency on vehicle-service.
// *client.VehicleClient satisfies it.
type VehicleValidator interface {
	GetVehicle(ctx context.Context, id int64) (client.Vehicle, error)
}

// NewRouter wires every route to its handler.
func NewRouter(store FuelStore, vehicles VehicleValidator) http.Handler {
	mux := http.NewServeMux()

	fuel := &FuelHandler{store: store, vehicles: vehicles}

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /vehicles/{id}/fuel-entries", fuel.List)
	mux.HandleFunc("POST /vehicles/{id}/fuel-entries", fuel.Create)

	return requestLogger(mux)
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(start))
	})
}
