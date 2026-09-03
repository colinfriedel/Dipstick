package handlers

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/colinfriedel/dipstick/activity-service/client"
	"github.com/colinfriedel/dipstick/activity-service/models"
)

// MaintenanceHandler serves the maintenance-entry endpoints.
type MaintenanceHandler struct {
	store    MaintenanceStore
	vehicles VehicleAPI
}

// List handles GET /vehicles/{id}/maintenance-entries.
func (h *MaintenanceHandler) List(w http.ResponseWriter, r *http.Request) {
	vehicleID, ok := parseVehicleID(w, r)
	if !ok {
		return
	}

	entries, err := h.store.ListMaintenanceEntries(r.Context(), vehicleID)
	if err != nil {
		log.Printf("List maintenance entries for vehicle %d: %v", vehicleID, err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, entries)
}

// Create handles POST /vehicles/{id}/maintenance-entries.
func (h *MaintenanceHandler) Create(w http.ResponseWriter, r *http.Request) {
	vehicleID, ok := parseVehicleID(w, r)
	if !ok {
		return
	}

	input, ok := decodeMaintenanceEntryInput(w, r)
	if !ok {
		return
	}

	// Same fail-closed vehicle check as fuel entries — no FK to fall back on.
	if _, err := h.vehicles.GetVehicle(r.Context(), vehicleID); err != nil {
		switch {
		case errors.Is(err, client.ErrVehicleNotFound):
			writeError(w, http.StatusUnprocessableEntity, "vehicle does not exist")
		case errors.Is(err, client.ErrVehicleServiceUnavailable):
			w.Header().Set("Retry-After", "10")
			writeError(w, http.StatusServiceUnavailable, "cannot verify the vehicle right now — please retry")
		default:
			log.Printf("Create maintenance entry: verifying vehicle %d: %v", vehicleID, err)
			writeError(w, http.StatusInternalServerError, "internal error")
		}
		return
	}

	created, err := h.store.CreateMaintenanceEntry(r.Context(), vehicleID, input)
	if err != nil {
		log.Printf("Create maintenance entry for vehicle %d: %v", vehicleID, err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusCreated, created)
}

// decodeMaintenanceEntryInput reads and validates the body. On success, Cost is
// guaranteed non-nil.
func decodeMaintenanceEntryInput(w http.ResponseWriter, r *http.Request) (models.MaintenanceEntryInput, bool) {
	var input models.MaintenanceEntryInput

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body: "+err.Error())
		return models.MaintenanceEntryInput{}, false
	}

	var problems []string
	if input.Date.IsZero() {
		problems = append(problems, "date is required (YYYY-MM-DD)")
	}
	if input.Odometer <= 0 {
		problems = append(problems, "odometer must be greater than 0")
	}
	if strings.TrimSpace(input.ServiceType) == "" {
		problems = append(problems, "serviceType is required")
	}
	if input.Cost != nil && *input.Cost < 0 {
		problems = append(problems, "cost cannot be negative")
	}
	for _, part := range input.PartsUsed {
		if strings.TrimSpace(part.Name) == "" {
			problems = append(problems, "partsUsed: every part needs a name")
			break
		}
		if part.Cost < 0 {
			problems = append(problems, "partsUsed: part costs cannot be negative")
			break
		}
	}
	if input.NextDueOdometer != nil && *input.NextDueOdometer <= input.Odometer {
		problems = append(problems, "nextDueOdometer must be greater than the entry's odometer")
	}
	if !input.NextDueDate.IsZero() && !input.Date.Before(input.NextDueDate) {
		problems = append(problems, "nextDueDate must be after the entry's date")
	}

	if len(problems) > 0 {
		writeError(w, http.StatusUnprocessableEntity, strings.Join(problems, "; "))
		return models.MaintenanceEntryInput{}, false
	}

	if input.Cost == nil {
		zero := 0.0
		input.Cost = &zero
	}

	return input, true
}
