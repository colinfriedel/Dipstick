// Package client is activity-service's outbound view of other services. Right
// now that's just vehicle-service, reached over HTTP.
//
// The architecture doc's core microservices lesson: activity-service does NOT
// read the vehicles table. When it needs to know a vehicle exists (or, later,
// its current odometer), it asks vehicle-service's API.
package client

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Sentinel errors so callers can react differently to "the vehicle genuinely
// isn't there" versus "we couldn't reach the service to find out".
var (
	// ErrVehicleNotFound means vehicle-service answered 404 — a definitive "no".
	ErrVehicleNotFound = errors.New("client: vehicle not found")
	// ErrVehicleServiceUnavailable means we couldn't get a usable answer:
	// timeout, connection refused, or a 5xx. The caller should treat this as
	// "try again later", not "the vehicle doesn't exist".
	ErrVehicleServiceUnavailable = errors.New("client: vehicle-service unavailable")
)

// Vehicle is the subset of vehicle-service's response this service uses.
type Vehicle struct {
	ID              int64  `json:"id"`
	Name            string `json:"name"`
	CurrentOdometer int    `json:"currentOdometer"`
}

// VehicleClient talks to vehicle-service.
type VehicleClient struct {
	baseURL string
	http    *http.Client
}

// NewVehicleClient builds a client for the given base URL (e.g.
// "http://vehicle-service:8080").
//
// We construct our own *http.Client with an explicit Timeout. http.DefaultClient
// has no timeout at all — a hung upstream would tie up the request goroutine and
// a connection indefinitely.
func NewVehicleClient(baseURL string) *VehicleClient {
	return &VehicleClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		http:    &http.Client{Timeout: 3 * time.Second},
	}
}

// GetVehicle fetches one vehicle by id.
//
// Retry policy: one extra attempt on a transient failure (network error or 5xx),
// with a short fixed backoff. A 404 is definitive and never retried. The retry
// is capped hard so a struggling upstream adds at most ~200ms of latency here.
func (c *VehicleClient) GetVehicle(ctx context.Context, id int64) (Vehicle, error) {
	url := fmt.Sprintf("%s/vehicles/%d", c.baseURL, id)

	const maxAttempts = 2
	var lastErr error

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		vehicle, err := c.getVehicleOnce(ctx, url)
		if err == nil {
			return vehicle, nil
		}
		if errors.Is(err, ErrVehicleNotFound) {
			return Vehicle{}, err
		}

		lastErr = err
		if attempt < maxAttempts {
			select {
			case <-time.After(200 * time.Millisecond):
			case <-ctx.Done():
				return Vehicle{}, ctx.Err()
			}
		}
	}

	// Wrap so callers can errors.Is(err, ErrVehicleServiceUnavailable) while the
	// underlying cause is still visible in logs.
	return Vehicle{}, fmt.Errorf("%w: %v", ErrVehicleServiceUnavailable, lastErr)
}

func (c *VehicleClient) getVehicleOnce(ctx context.Context, url string) (Vehicle, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return Vehicle{}, err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return Vehicle{}, err // network-level failure: transient
	}
	defer resp.Body.Close()

	switch {
	case resp.StatusCode == http.StatusOK:
		var vehicle Vehicle
		if err := json.NewDecoder(resp.Body).Decode(&vehicle); err != nil {
			return Vehicle{}, fmt.Errorf("decoding vehicle response: %w", err)
		}
		return vehicle, nil

	case resp.StatusCode == http.StatusNotFound:
		return Vehicle{}, ErrVehicleNotFound

	default:
		return Vehicle{}, fmt.Errorf("vehicle-service returned status %d", resp.StatusCode)
	}
}
