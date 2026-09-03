package handlers

import (
	"log"
	"net/http"
	"time"

	"github.com/colinfriedel/dipstick/activity-service/models"
	"github.com/colinfriedel/dipstick/activity-service/service"
)

// DueHandler serves GET /due — the cross-vehicle "what maintenance is due soon
// or overdue" view.
type DueHandler struct {
	store    MaintenanceStore
	vehicles VehicleAPI
	config   service.DueConfig
}

type dueResponse struct {
	Items       []models.DueItem `json:"items"`
	GeneratedAt string           `json:"generatedAt"`
	// Warnings is present only when the result is degraded — e.g. vehicle-service
	// was unreachable so mileage checks were skipped.
	Warnings []string `json:"warnings,omitempty"`
}

// List handles GET /due.
func (h *DueHandler) List(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// The most recent entry for every (vehicle, service type) — one query.
	latest, err := h.store.LatestMaintenancePerService(ctx)
	if err != nil {
		log.Printf("Due: loading latest maintenance: %v", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	var warnings []string

	// Current odometers come from vehicle-service. If it's down we degrade to
	// date-based checks only rather than failing the whole endpoint.
	odometers := map[int64]int{}
	haveVehicleList := false
	if vehicles, err := h.vehicles.ListVehicles(ctx); err != nil {
		warnings = append(warnings,
			"vehicle-service was unreachable: mileage-based checks were skipped, and results may include vehicles that no longer exist")
	} else {
		haveVehicleList = true
		for _, v := range vehicles {
			odometers[v.ID] = v.CurrentOdometer
		}
	}

	// Group the latest entries by vehicle, skipping orphaned ones when we can
	// tell (a vehicle that vehicle-service no longer lists).
	byVehicle := map[int64][]models.MaintenanceEntry{}
	for _, entry := range latest {
		if haveVehicleList {
			if _, exists := odometers[entry.VehicleID]; !exists {
				continue
			}
		}
		byVehicle[entry.VehicleID] = append(byVehicle[entry.VehicleID], entry)
	}

	input := make([]service.VehicleMaintenance, 0, len(byVehicle))
	for vehicleID, entries := range byVehicle {
		vm := service.VehicleMaintenance{
			VehicleID:       vehicleID,
			LatestByService: entries,
		}
		if odo, ok := odometers[vehicleID]; ok {
			odo := odo
			vm.CurrentOdometer = &odo
		}
		input = append(input, vm)
	}

	items := service.CalculateDue(input, models.Today(), h.config)
	if items == nil {
		items = []models.DueItem{}
	}

	writeJSON(w, http.StatusOK, dueResponse{
		Items:       items,
		GeneratedAt: time.Now().UTC().Format(time.RFC3339),
		Warnings:    warnings,
	})
}
