// Package models holds the plain data types that move between the database,
// the business logic, and the JSON API. They contain no behavior — just fields.
package models

// Vehicle mirrors one row of the vehicle.vehicles table.
//
// The nullable columns (year, make, model, vin) are modeled as pointers so we
// can tell "the user didn't provide this" (nil) apart from a real zero value
// like year 0 or an empty make string. A nil pointer marshals to JSON `null`.
type Vehicle struct {
	ID              int64   `json:"id"`
	Name            string  `json:"name"`
	Year            *int    `json:"year"`
	Make            *string `json:"make"`
	Model           *string `json:"model"`
	VIN             *string `json:"vin"`
	CurrentOdometer int     `json:"currentOdometer"`
}

// VehicleInput is the shape of the JSON body the client sends when creating or
// updating a vehicle. It deliberately omits ID (the server owns that) and is
// kept separate from Vehicle so the "what the client may set" contract is
// explicit rather than implied.
type VehicleInput struct {
	Name            string  `json:"name"`
	Year            *int    `json:"year"`
	Make            *string `json:"make"`
	Model           *string `json:"model"`
	VIN             *string `json:"vin"`
	CurrentOdometer int     `json:"currentOdometer"`
}
