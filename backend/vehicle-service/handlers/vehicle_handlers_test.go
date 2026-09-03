package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/colinfriedel/dipstick/vehicle-service/models"
	"github.com/colinfriedel/dipstick/vehicle-service/store"
)

// fakeStore is an in-memory stand-in for the real database-backed store. It
// satisfies the VehicleStore interface, so NewRouter accepts it. Each field lets
// a test say "when this method is called, behave like this".
type fakeStore struct {
	vehicles  []models.Vehicle
	getResult models.Vehicle
	getErr    error
	created   models.VehicleInput
}

func (f *fakeStore) ListVehicles(ctx context.Context) ([]models.Vehicle, error) {
	// Mirror the real store's contract: never return a nil slice.
	if f.vehicles == nil {
		return []models.Vehicle{}, nil
	}
	return f.vehicles, nil
}

func (f *fakeStore) GetVehicle(ctx context.Context, id int64) (models.Vehicle, error) {
	return f.getResult, f.getErr
}

func (f *fakeStore) CreateVehicle(ctx context.Context, in models.VehicleInput) (models.Vehicle, error) {
	f.created = in
	return models.Vehicle{ID: 1, Name: in.Name, CurrentOdometer: in.CurrentOdometer}, nil
}

func (f *fakeStore) UpdateVehicle(ctx context.Context, id int64, in models.VehicleInput) (models.Vehicle, error) {
	return models.Vehicle{ID: id, Name: in.Name}, nil
}

func (f *fakeStore) DeleteVehicle(ctx context.Context, id int64) error {
	return nil
}

// doRequest runs one request through the real router against the given fake
// store and returns the recorded response.
func doRequest(t *testing.T, fs *fakeStore, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rec := httptest.NewRecorder()
	NewRouter(fs).ServeHTTP(rec, req)
	return rec
}

func TestCreateVehicle_Valid(t *testing.T) {
	fs := &fakeStore{}
	rec := doRequest(t, fs, http.MethodPost, "/vehicles", `{"name":"Daily Driver","currentOdometer":42000}`)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d (body: %s)", rec.Code, http.StatusCreated, rec.Body)
	}
	if fs.created.Name != "Daily Driver" || fs.created.CurrentOdometer != 42000 {
		t.Fatalf("store received %+v, want name=Daily Driver odo=42000", fs.created)
	}

	var got models.Vehicle
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if got.ID != 1 {
		t.Fatalf("response ID = %d, want 1", got.ID)
	}
}

func TestCreateVehicle_MissingName(t *testing.T) {
	fs := &fakeStore{}
	rec := doRequest(t, fs, http.MethodPost, "/vehicles", `{"currentOdometer":100}`)

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnprocessableEntity)
	}
}

func TestCreateVehicle_BadJSON(t *testing.T) {
	fs := &fakeStore{}
	rec := doRequest(t, fs, http.MethodPost, "/vehicles", `{"name": "oops"`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestCreateVehicle_UnknownField(t *testing.T) {
	fs := &fakeStore{}
	rec := doRequest(t, fs, http.MethodPost, "/vehicles", `{"name":"x","colour":"red"}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestGetVehicle_NotFound(t *testing.T) {
	fs := &fakeStore{getErr: store.ErrNotFound}
	rec := doRequest(t, fs, http.MethodGet, "/vehicles/999", "")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

func TestGetVehicle_BadID(t *testing.T) {
	fs := &fakeStore{}
	rec := doRequest(t, fs, http.MethodGet, "/vehicles/abc", "")

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestListVehicles_EmptyIsJSONArray(t *testing.T) {
	fs := &fakeStore{}
	rec := doRequest(t, fs, http.MethodGet, "/vehicles", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != "[]" {
		t.Fatalf("body = %q, want %q", got, "[]")
	}
}
