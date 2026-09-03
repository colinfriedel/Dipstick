package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/colinfriedel/dipstick/activity-service/client"
	"github.com/colinfriedel/dipstick/activity-service/models"
)

// --- fakes ---

type fakeFuelStore struct {
	entries   []models.FuelEntry
	created   *models.FuelEntryInput
	createErr error
}

func (f *fakeFuelStore) ListFuelEntries(ctx context.Context, vehicleID int64) ([]models.FuelEntry, error) {
	return f.entries, nil
}

func (f *fakeFuelStore) CreateFuelEntry(ctx context.Context, vehicleID int64, in models.FuelEntryInput) (models.FuelEntry, error) {
	if f.createErr != nil {
		return models.FuelEntry{}, f.createErr
	}
	f.created = &in
	e := models.FuelEntry{
		ID:         100,
		VehicleID:  vehicleID,
		Date:       in.Date,
		Odometer:   in.Odometer,
		Gallons:    in.Gallons,
		TotalCost:  *in.TotalCost,
		IsFullTank: *in.IsFullTank,
	}
	f.entries = append(f.entries, e)
	return e, nil
}

type fakeVehicleValidator struct {
	err error
}

func (f *fakeVehicleValidator) GetVehicle(ctx context.Context, id int64) (client.Vehicle, error) {
	if f.err != nil {
		return client.Vehicle{}, f.err
	}
	return client.Vehicle{ID: id, Name: "Test Car", CurrentOdometer: 50000}, nil
}

func doRequest(t *testing.T, store FuelStore, vehicles VehicleValidator, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rec := httptest.NewRecorder()
	NewRouter(store, vehicles).ServeHTTP(rec, req)
	return rec
}

// --- tests ---

func TestCreateFuelEntry_Valid(t *testing.T) {
	store := &fakeFuelStore{}
	vehicles := &fakeVehicleValidator{}

	body := `{"date":"2024-03-14","odometer":42000,"gallons":10.5,"totalCost":38.25,"isFullTank":true}`
	rec := doRequest(t, store, vehicles, http.MethodPost, "/vehicles/7/fuel-entries", body)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (body: %s)", rec.Code, rec.Body)
	}
	if store.created == nil {
		t.Fatal("store.CreateFuelEntry was not called")
	}
	if *store.created.TotalCost != 38.25 {
		t.Errorf("stored totalCost = %v, want 38.25", *store.created.TotalCost)
	}

	var got models.FuelEntry
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("response not valid JSON: %v", err)
	}
	if got.VehicleID != 7 {
		t.Errorf("response vehicleId = %d, want 7", got.VehicleID)
	}
	if got.Date.String() != "2024-03-14" {
		t.Errorf("response date = %q, want 2024-03-14", got.Date.String())
	}
}

func TestCreateFuelEntry_DerivesTotalCostFromPricePerGallon(t *testing.T) {
	store := &fakeFuelStore{}
	body := `{"date":"2024-03-14","odometer":42000,"gallons":10,"pricePerGallon":3.50}`
	rec := doRequest(t, store, &fakeVehicleValidator{}, http.MethodPost, "/vehicles/1/fuel-entries", body)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (body: %s)", rec.Code, rec.Body)
	}
	if store.created == nil || *store.created.TotalCost != 35.0 {
		t.Fatalf("derived totalCost = %v, want 35.0", store.created)
	}
}

func TestCreateFuelEntry_DefaultsIsFullTankToTrue(t *testing.T) {
	store := &fakeFuelStore{}
	body := `{"date":"2024-03-14","odometer":42000,"gallons":10,"totalCost":30}`
	rec := doRequest(t, store, &fakeVehicleValidator{}, http.MethodPost, "/vehicles/1/fuel-entries", body)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201", rec.Code)
	}
	if store.created == nil || *store.created.IsFullTank != true {
		t.Fatalf("isFullTank = %v, want true", store.created)
	}
}

func TestCreateFuelEntry_MissingCost(t *testing.T) {
	rec := doRequest(t, &fakeFuelStore{}, &fakeVehicleValidator{}, http.MethodPost,
		"/vehicles/1/fuel-entries", `{"date":"2024-03-14","odometer":42000,"gallons":10}`)

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", rec.Code)
	}
}

func TestCreateFuelEntry_BadDate(t *testing.T) {
	rec := doRequest(t, &fakeFuelStore{}, &fakeVehicleValidator{}, http.MethodPost,
		"/vehicles/1/fuel-entries", `{"date":"March 14","odometer":42000,"gallons":10,"totalCost":30}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (bad date is a decode error)", rec.Code)
	}
}

func TestCreateFuelEntry_VehicleNotFound(t *testing.T) {
	vehicles := &fakeVehicleValidator{err: client.ErrVehicleNotFound}
	rec := doRequest(t, &fakeFuelStore{}, vehicles, http.MethodPost,
		"/vehicles/999/fuel-entries", `{"date":"2024-03-14","odometer":42000,"gallons":10,"totalCost":30}`)

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", rec.Code)
	}
}

func TestCreateFuelEntry_VehicleServiceUnavailable(t *testing.T) {
	vehicles := &fakeVehicleValidator{err: client.ErrVehicleServiceUnavailable}
	store := &fakeFuelStore{}
	rec := doRequest(t, store, vehicles, http.MethodPost,
		"/vehicles/7/fuel-entries", `{"date":"2024-03-14","odometer":42000,"gallons":10,"totalCost":30}`)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Error("expected a Retry-After header on 503")
	}
	if store.created != nil {
		t.Error("no entry should be written when the vehicle can't be verified (fail closed)")
	}
}

func TestListFuelEntries_ComputesMPG(t *testing.T) {
	store := &fakeFuelStore{entries: []models.FuelEntry{
		{ID: 2, VehicleID: 1, Odometer: 1300, Gallons: 10, TotalCost: 35, IsFullTank: true,
			Date: models.Date{Year: 2024, Month: 2, Day: 1}},
		{ID: 1, VehicleID: 1, Odometer: 1000, Gallons: 10, TotalCost: 30, IsFullTank: true,
			Date: models.Date{Year: 2024, Month: 1, Day: 1}},
	}}

	rec := doRequest(t, store, &fakeVehicleValidator{}, http.MethodGet, "/vehicles/1/fuel-entries", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}

	var got []models.FuelEntry
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("response not valid JSON: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d entries, want 2", len(got))
	}

	byID := map[int64]models.FuelEntry{got[0].ID: got[0], got[1].ID: got[1]}
	if byID[1].MPG != nil {
		t.Errorf("entry 1 (first full tank) MPG = %v, want null", *byID[1].MPG)
	}
	if byID[2].MPG == nil || *byID[2].MPG != 30 {
		t.Errorf("entry 2 MPG = %v, want 30", byID[2].MPG)
	}
	if byID[2].CostPerGallon != 3.5 {
		t.Errorf("entry 2 costPerGallon = %v, want 3.5", byID[2].CostPerGallon)
	}
}

func TestListFuelEntries_EmptyIsJSONArray(t *testing.T) {
	rec := doRequest(t, &fakeFuelStore{entries: []models.FuelEntry{}}, &fakeVehicleValidator{},
		http.MethodGet, "/vehicles/1/fuel-entries", "")

	if got := strings.TrimSpace(rec.Body.String()); got != "[]" {
		t.Fatalf("body = %q, want []", got)
	}
}
