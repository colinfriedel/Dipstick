package models

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
)

// Part is one line item under a maintenance entry — "name + cost", repeatable.
type Part struct {
	Name string  `json:"name"`
	Cost float64 `json:"cost"`
}

// Parts is a slice of Part that knows how to store itself in a single JSONB
// column. Same idea as the Date type: implement the DB-boundary interfaces so
// the rest of the code just uses a normal Go slice.
//
//	Go   -> DB : Value marshals the slice to JSON bytes (nil slice -> SQL NULL)
//	DB   -> Go : Scan unmarshals the column's JSON bytes back into the slice
type Parts []Part

// Value implements driver.Valuer.
func (p Parts) Value() (driver.Value, error) {
	if p == nil {
		return nil, nil
	}
	return json.Marshal(p)
}

// Scan implements sql.Scanner.
func (p *Parts) Scan(src any) error {
	if src == nil {
		*p = nil
		return nil
	}

	var data []byte
	switch v := src.(type) {
	case []byte:
		data = v
	case string:
		data = []byte(v)
	default:
		return fmt.Errorf("cannot scan %T into models.Parts", src)
	}

	return json.Unmarshal(data, p)
}

// MaintenanceEntry mirrors a row of activity.maintenance_entries.
type MaintenanceEntry struct {
	ID          int64   `json:"id"`
	VehicleID   int64   `json:"vehicleId"`
	Date        Date    `json:"date"`
	Odometer    int     `json:"odometer"`
	ServiceType string  `json:"serviceType"`
	Cost        float64 `json:"cost"`
	PartsUsed   Parts   `json:"partsUsed"`
	Notes       *string `json:"notes"`

	// The "next due" for this service type, either of which may be unset.
	// NextDueOdometer is a pointer (nil = unset); NextDueDate uses the zero
	// value as "unset" (it marshals to null).
	NextDueOdometer *int `json:"nextDueOdometer"`
	NextDueDate     Date `json:"nextDueDate"`
}

// MaintenanceEntryInput is the JSON body for POST
// /vehicles/{id}/maintenance-entries.
//
// After decodeMaintenanceEntryInput validates it, Cost is guaranteed non-nil
// (defaulting to 0, matching the column default).
type MaintenanceEntryInput struct {
	Date            Date     `json:"date"`
	Odometer        int      `json:"odometer"`
	ServiceType     string   `json:"serviceType"`
	Cost            *float64 `json:"cost"`
	PartsUsed       Parts    `json:"partsUsed"`
	Notes           *string  `json:"notes"`
	NextDueOdometer *int     `json:"nextDueOdometer"`
	NextDueDate     Date     `json:"nextDueDate"`
}

// DueStatus is where a service sits relative to its next-due target.
type DueStatus string

const (
	DueSoon DueStatus = "due_soon"
	Overdue DueStatus = "overdue"
)

// DueItem is one row of the GET /due response: a (vehicle, service type) pair
// that needs attention, plus the numbers explaining why.
type DueItem struct {
	VehicleID   int64     `json:"vehicleId"`
	ServiceType string    `json:"serviceType"`
	Status      DueStatus `json:"status"`

	// Whichever dimensions have a target set. Negative means "past due by this
	// much". Fields are omitted when that dimension has no target.
	MilesRemaining *int `json:"milesRemaining,omitempty"`
	DaysRemaining  *int `json:"daysRemaining,omitempty"`

	// Context for the client / the human reading it.
	NextDueOdometer     *int `json:"nextDueOdometer"`
	NextDueDate         Date `json:"nextDueDate"`
	LastServiceOdometer int  `json:"lastServiceOdometer"`
	LastServiceDate     Date `json:"lastServiceDate"`
}
