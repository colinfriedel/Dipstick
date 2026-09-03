package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/colinfriedel/dipstick/vehicle-service/models"
	"github.com/colinfriedel/dipstick/vehicle-service/store"
)

// VehicleStore is the slice of the data layer these handlers need.
//
// Idiomatic Go: the *consumer* declares the interface, listing only the methods
// it actually calls. *store.Store satisfies this implicitly (no "implements"
// keyword), and tests can pass a tiny fake instead of a real database.
type VehicleStore interface {
	ListVehicles(ctx context.Context) ([]models.Vehicle, error)
	GetVehicle(ctx context.Context, id int64) (models.Vehicle, error)
	CreateVehicle(ctx context.Context, in models.VehicleInput) (models.Vehicle, error)
	UpdateVehicle(ctx context.Context, id int64, in models.VehicleInput) (models.Vehicle, error)
	DeleteVehicle(ctx context.Context, id int64) error
}

// VehicleHandler groups the vehicle endpoints and holds their one dependency.
// Holding it as a field (rather than a package-level variable) keeps the
// dependency explicit and swappable.
type VehicleHandler struct {
	store VehicleStore
}

// List handles GET /vehicles.
func (h *VehicleHandler) List(w http.ResponseWriter, r *http.Request) {
	vehicles, err := h.store.ListVehicles(r.Context())
	if err != nil {
		log.Printf("List vehicles: %v", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, vehicles)
}

// Get handles GET /vehicles/{id}.
func (h *VehicleHandler) Get(w http.ResponseWriter, r *http.Request) {
	id, ok := parseID(w, r)
	if !ok {
		return
	}

	vehicle, err := h.store.GetVehicle(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "vehicle not found")
		return
	}
	if err != nil {
		log.Printf("Get vehicle %d: %v", id, err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, vehicle)
}

// Create handles POST /vehicles.
func (h *VehicleHandler) Create(w http.ResponseWriter, r *http.Request) {
	input, ok := decodeVehicleInput(w, r)
	if !ok {
		return
	}

	vehicle, err := h.store.CreateVehicle(r.Context(), input)
	if err != nil {
		log.Printf("Create vehicle: %v", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusCreated, vehicle)
}

// Update handles PUT /vehicles/{id}.
func (h *VehicleHandler) Update(w http.ResponseWriter, r *http.Request) {
	id, ok := parseID(w, r)
	if !ok {
		return
	}
	input, ok := decodeVehicleInput(w, r)
	if !ok {
		return
	}

	vehicle, err := h.store.UpdateVehicle(r.Context(), id, input)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "vehicle not found")
		return
	}
	if err != nil {
		log.Printf("Update vehicle %d: %v", id, err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, vehicle)
}

// Delete handles DELETE /vehicles/{id}.
func (h *VehicleHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id, ok := parseID(w, r)
	if !ok {
		return
	}

	err := h.store.DeleteVehicle(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "vehicle not found")
		return
	}
	if err != nil {
		log.Printf("Delete vehicle %d: %v", id, err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	// 204 No Content: success, nothing to send back.
	w.WriteHeader(http.StatusNoContent)
}

// parseID pulls {id} from the path and parses it. On failure it writes a 400 and
// returns ok == false, so callers just do: id, ok := parseID(...); if !ok { return }
func parseID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	raw := r.PathValue("id")
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "invalid vehicle id")
		return 0, false
	}
	return id, true
}

// decodeVehicleInput reads and validates the JSON request body.
func decodeVehicleInput(w http.ResponseWriter, r *http.Request) (models.VehicleInput, bool) {
	var input models.VehicleInput

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields() // reject typos in field names instead of ignoring them
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body: "+err.Error())
		return models.VehicleInput{}, false
	}

	if strings.TrimSpace(input.Name) == "" {
		// 422 Unprocessable Entity: the JSON parsed fine, but a business rule
		// (name is required) failed.
		writeError(w, http.StatusUnprocessableEntity, "name is required")
		return models.VehicleInput{}, false
	}
	if input.CurrentOdometer < 0 {
		writeError(w, http.StatusUnprocessableEntity, "currentOdometer cannot be negative")
		return models.VehicleInput{}, false
	}

	return input, true
}
