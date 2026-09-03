package handlers

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/colinfriedel/dipstick/activity-service/client"
	"github.com/colinfriedel/dipstick/activity-service/models"
	"github.com/colinfriedel/dipstick/activity-service/service"
)

// FuelHandler serves the fuel-entry endpoints. It depends on the data layer and
// on vehicle-service (via VehicleValidator).
type FuelHandler struct {
	store    FuelStore
	vehicles VehicleValidator
}

// List handles GET /vehicles/{id}/fuel-entries.
//
// This read is NOT gated on vehicle-service being reachable — an unknown vehicle
// simply has no entries and returns []. Keeping reads independent of the other
// service's availability is intentional (see the architecture doc's "degrade
// reads, don't fail them" note).
func (h *FuelHandler) List(w http.ResponseWriter, r *http.Request) {
	vehicleID, ok := parseVehicleID(w, r)
	if !ok {
		return
	}

	entries, err := h.store.ListFuelEntries(r.Context(), vehicleID)
	if err != nil {
		log.Printf("List fuel entries for vehicle %d: %v", vehicleID, err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	service.EnrichFuelEntries(entries)
	writeJSON(w, http.StatusOK, entries)
}

// Create handles POST /vehicles/{id}/fuel-entries.
func (h *FuelHandler) Create(w http.ResponseWriter, r *http.Request) {
	vehicleID, ok := parseVehicleID(w, r)
	if !ok {
		return
	}

	input, ok := decodeFuelEntryInput(w, r)
	if !ok {
		return
	}

	// Validate the vehicle exists by asking vehicle-service. We have no foreign
	// key to lean on, so this check is the only thing standing between a typo'd
	// vehicle id and a fuel entry that silently corrupts that vehicle's MPG
	// history forever. So we fail closed: if we can't confirm the vehicle, we
	// don't write.
	if _, err := h.vehicles.GetVehicle(r.Context(), vehicleID); err != nil {
		switch {
		case errors.Is(err, client.ErrVehicleNotFound):
			writeError(w, http.StatusUnprocessableEntity, "vehicle does not exist")
		case errors.Is(err, client.ErrVehicleServiceUnavailable):
			w.Header().Set("Retry-After", "10")
			writeError(w, http.StatusServiceUnavailable, "cannot verify the vehicle right now — please retry")
		default:
			log.Printf("Create fuel entry: verifying vehicle %d: %v", vehicleID, err)
			writeError(w, http.StatusInternalServerError, "internal error")
		}
		return
	}

	created, err := h.store.CreateFuelEntry(r.Context(), vehicleID, input)
	if err != nil {
		log.Printf("Create fuel entry for vehicle %d: %v", vehicleID, err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	// Reload the full history so the response can carry this entry's derived
	// fields — a new full tank may now close an MPG interval.
	all, err := h.store.ListFuelEntries(r.Context(), vehicleID)
	if err != nil {
		// The entry is already saved. Don't turn a post-save read failure into
		// a 500 — just return the entry without the derived fields.
		log.Printf("Create fuel entry: reloading history for vehicle %d: %v", vehicleID, err)
		writeJSON(w, http.StatusCreated, created)
		return
	}

	service.EnrichFuelEntries(all)

	result := created
	for _, e := range all {
		if e.ID == created.ID {
			result = e
			break
		}
	}
	writeJSON(w, http.StatusCreated, result)
}

// parseVehicleID reads {id} from the path.
func parseVehicleID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "invalid vehicle id")
		return 0, false
	}
	return id, true
}

// decodeFuelEntryInput reads and validates the request body. On success the
// returned input has TotalCost and IsFullTank guaranteed non-nil.
func decodeFuelEntryInput(w http.ResponseWriter, r *http.Request) (models.FuelEntryInput, bool) {
	var input models.FuelEntryInput

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body: "+err.Error())
		return models.FuelEntryInput{}, false
	}

	var problems []string
	if input.Date.IsZero() {
		problems = append(problems, "date is required (YYYY-MM-DD)")
	}
	if input.Odometer <= 0 {
		problems = append(problems, "odometer must be greater than 0")
	}
	if input.Gallons <= 0 {
		problems = append(problems, "gallons must be greater than 0")
	}
	if input.TotalCost != nil && *input.TotalCost < 0 {
		problems = append(problems, "totalCost cannot be negative")
	}
	if input.PricePerGallon != nil && *input.PricePerGallon < 0 {
		problems = append(problems, "pricePerGallon cannot be negative")
	}
	if input.TotalCost == nil && input.PricePerGallon == nil {
		problems = append(problems, "either totalCost or pricePerGallon is required")
	}

	if len(problems) > 0 {
		writeError(w, http.StatusUnprocessableEntity, strings.Join(problems, "; "))
		return models.FuelEntryInput{}, false
	}

	// Normalize so downstream code never has to re-check.
	if input.TotalCost == nil {
		cost := *input.PricePerGallon * input.Gallons
		input.TotalCost = &cost
	}
	if input.IsFullTank == nil {
		fullTank := true // matches the column's DEFAULT TRUE
		input.IsFullTank = &fullTank
	}

	return input, true
}
