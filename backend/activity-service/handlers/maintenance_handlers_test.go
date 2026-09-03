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
	"github.com/colinfriedel/dipstick/activity-service/service"
)

type fakeMaintenanceStore struct {
	entries []models.MaintenanceEntry
	latest  []models.MaintenanceEntry
	created *models.MaintenanceEntryInput
}

func (f *fakeMaintenanceStore) ListMaintenanceEntries(ctx context.Context, vehicleID int64) ([]models.MaintenanceEntry, error) {
	return f.entries, nil
}

func (f *fakeMaintenanceStore) CreateMaintenanceEntry(ctx context.Context, vehicleID int64, in models.MaintenanceEntryInput) (models.MaintenanceEntry, error) {
	f.created = &in
	return models.MaintenanceEntry{
		ID:              200,
		VehicleID:       vehicleID,
		Date:            in.Date,
		Odometer:        in.Odometer,
		ServiceType:     in.ServiceType,
		Cost:            *in.Cost,
		PartsUsed:       in.PartsUsed,
		NextDueOdometer: in.NextDueOdometer,
		NextDueDate:     in.NextDueDate,
	}, nil
}

func (f *fakeMaintenanceStore) LatestMaintenancePerService(ctx context.Context) ([]models.MaintenanceEntry, error) {
	return f.latest, nil
}

func doMaintRequest(t *testing.T, deps Deps, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rec := httptest.NewRecorder()
	NewRouter(deps).ServeHTTP(rec, req)
	return rec
}

func TestCreateMaintenanceEntry_Valid(t *testing.T) {
	store := &fakeMaintenanceStore{}
	deps := Deps{Maintenance: store, Vehicles: &fakeVehicleAPI{}}

	body := `{
		"date":"2024-03-14","odometer":42000,"serviceType":"oil change","cost":65.00,
		"partsUsed":[{"name":"filter","cost":12.50},{"name":"5qt 5W-30","cost":34.00}],
		"nextDueOdometer":47000,"nextDueDate":"2024-09-14"
	}`
	rec := doMaintRequest(t, deps, http.MethodPost, "/vehicles/3/maintenance-entries", body)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (body: %s)", rec.Code, rec.Body)
	}
	if store.created == nil {
		t.Fatal("CreateMaintenanceEntry was not called")
	}
	if len(store.created.PartsUsed) != 2 || store.created.PartsUsed[0].Name != "filter" {
		t.Errorf("parts not parsed: %+v", store.created.PartsUsed)
	}

	var got models.MaintenanceEntry
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("response not valid JSON: %v", err)
	}
	if got.NextDueOdometer == nil || *got.NextDueOdometer != 47000 {
		t.Errorf("nextDueOdometer = %v, want 47000", got.NextDueOdometer)
	}
	if got.NextDueDate.String() != "2024-09-14" {
		t.Errorf("nextDueDate = %q, want 2024-09-14", got.NextDueDate.String())
	}
}

func TestCreateMaintenanceEntry_DefaultsCostToZero(t *testing.T) {
	store := &fakeMaintenanceStore{}
	deps := Deps{Maintenance: store, Vehicles: &fakeVehicleAPI{}}

	body := `{"date":"2024-03-14","odometer":42000,"serviceType":"tire rotation"}`
	rec := doMaintRequest(t, deps, http.MethodPost, "/vehicles/1/maintenance-entries", body)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (body: %s)", rec.Code, rec.Body)
	}
	if store.created == nil || *store.created.Cost != 0 {
		t.Fatalf("cost = %v, want 0", store.created)
	}
}

func TestCreateMaintenanceEntry_Validation(t *testing.T) {
	deps := Deps{Maintenance: &fakeMaintenanceStore{}, Vehicles: &fakeVehicleAPI{}}

	cases := map[string]string{
		"missing serviceType":         `{"date":"2024-03-14","odometer":42000}`,
		"nextDueOdometer <= odometer": `{"date":"2024-03-14","odometer":42000,"serviceType":"x","nextDueOdometer":42000}`,
		"nextDueDate before date":     `{"date":"2024-03-14","odometer":42000,"serviceType":"x","nextDueDate":"2024-01-01"}`,
		"negative part cost":          `{"date":"2024-03-14","odometer":42000,"serviceType":"x","partsUsed":[{"name":"y","cost":-1}]}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			rec := doMaintRequest(t, deps, http.MethodPost, "/vehicles/1/maintenance-entries", body)
			if rec.Code != http.StatusUnprocessableEntity {
				t.Fatalf("status = %d, want 422 (body: %s)", rec.Code, rec.Body)
			}
		})
	}
}

func TestDue_ComputesAcrossVehicles(t *testing.T) {
	oil := models.MaintenanceEntry{
		VehicleID: 1, ServiceType: "oil change", Odometer: 45000,
		Date:            models.Date{Year: 2024, Month: 1, Day: 1},
		NextDueOdometer: ptrInt(50200),
	}
	tires := models.MaintenanceEntry{
		VehicleID: 2, ServiceType: "tire rotation", Odometer: 20000,
		Date:            models.Date{Year: 2024, Month: 1, Day: 1},
		NextDueOdometer: ptrInt(18000), // overdue
	}
	store := &fakeMaintenanceStore{latest: []models.MaintenanceEntry{oil, tires}}
	vehicles := &fakeVehicleAPI{list: []client.Vehicle{
		{ID: 1, CurrentOdometer: 50000},
		{ID: 2, CurrentOdometer: 30000},
	}}
	deps := Deps{Maintenance: store, Vehicles: vehicles, DueConfig: service.DefaultDueConfig()}

	rec := doMaintRequest(t, deps, http.MethodGet, "/due", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}

	var resp dueResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response not valid JSON: %v", err)
	}
	if len(resp.Items) != 2 {
		t.Fatalf("got %d due items, want 2: %+v", len(resp.Items), resp.Items)
	}
	if resp.Items[0].ServiceType != "tire rotation" || resp.Items[0].Status != models.Overdue {
		t.Errorf("first item = %+v, want overdue tire rotation", resp.Items[0])
	}
	if len(resp.Warnings) != 0 {
		t.Errorf("unexpected warnings: %v", resp.Warnings)
	}
}

func TestDue_DegradesWhenVehicleServiceDown(t *testing.T) {
	// Only a mileage target — with no odometer available it can't be evaluated.
	mileageOnly := models.MaintenanceEntry{
		VehicleID: 1, ServiceType: "oil change", Odometer: 45000,
		Date:            models.Date{Year: 2024, Month: 1, Day: 1},
		NextDueOdometer: ptrInt(46000),
	}
	// A date target in the past — still evaluable without an odometer.
	dateOverdue := models.MaintenanceEntry{
		VehicleID: 1, ServiceType: "registration", Odometer: 45000,
		Date:        models.Date{Year: 2023, Month: 1, Day: 1},
		NextDueDate: models.Date{Year: 2023, Month: 6, Day: 1},
	}
	store := &fakeMaintenanceStore{latest: []models.MaintenanceEntry{mileageOnly, dateOverdue}}
	vehicles := &fakeVehicleAPI{err: client.ErrVehicleServiceUnavailable}
	deps := Deps{Maintenance: store, Vehicles: vehicles, DueConfig: service.DefaultDueConfig()}

	rec := doMaintRequest(t, deps, http.MethodGet, "/due", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (degraded, not failed)", rec.Code)
	}

	var resp dueResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response not valid JSON: %v", err)
	}
	if len(resp.Warnings) == 0 {
		t.Error("expected a warning about vehicle-service being unreachable")
	}
	if len(resp.Items) != 1 || resp.Items[0].ServiceType != "registration" {
		t.Fatalf("want just the date-based item, got %+v", resp.Items)
	}
}

func ptrInt(v int) *int { return &v }
