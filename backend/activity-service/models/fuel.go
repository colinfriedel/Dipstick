// Package models holds the plain data types that move between the database, the
// business logic, and the JSON API. No behavior beyond the small marshaling
// helpers on Date.
package models

// FuelEntry is one logged fuel stop, mirroring a row of activity.fuel_entries
// plus two derived fields (CostPerGallon, MPG) that the service computes and the
// database never stores.
type FuelEntry struct {
	ID          int64   `json:"id"`
	VehicleID   int64   `json:"vehicleId"`
	Date        Date    `json:"date"`
	Odometer    int     `json:"odometer"`
	Gallons     float64 `json:"gallons"`
	TotalCost   float64 `json:"totalCost"`
	IsFullTank  bool    `json:"isFullTank"`
	StationName *string `json:"stationName"`
	Notes       *string `json:"notes"`

	// Derived, not persisted:

	// CostPerGallon is TotalCost / Gallons.
	CostPerGallon float64 `json:"costPerGallon"`
	// MPG is set only when this entry closes an interval between two consecutive
	// full-tank fill-ups. nil (JSON null) means "not calculable for this entry"
	// — a partial fill-up, the first-ever full tank, or insufficient data.
	MPG *float64 `json:"mpg"`
}

// FuelEntryInput is the JSON body accepted by POST /vehicles/{id}/fuel-entries.
//
// TotalCost and PricePerGallon are both optional and pointer-typed: the client
// sends whichever it knows and the server derives the other. After
// decodeFuelEntryInput validates the body, TotalCost is guaranteed non-nil and
// IsFullTank is guaranteed non-nil (defaulting to true, matching the column
// default), so downstream code can dereference them freely.
type FuelEntryInput struct {
	Date           Date     `json:"date"`
	Odometer       int      `json:"odometer"`
	Gallons        float64  `json:"gallons"`
	TotalCost      *float64 `json:"totalCost"`
	PricePerGallon *float64 `json:"pricePerGallon"`
	IsFullTank     *bool    `json:"isFullTank"`
	StationName    *string  `json:"stationName"`
	Notes          *string  `json:"notes"`
}
