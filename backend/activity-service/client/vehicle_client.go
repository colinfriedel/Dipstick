// Package client is activity-service's outbound view of other services. Right
// now that's just vehicle-service, reached over HTTP.
//
// The architecture doc's core microservices lesson: activity-service does NOT
// read the vehicles table. When it needs to know a vehicle exists, or needs the
// fleet's current odometers for the /due calculation, it asks vehicle-service's
// API.
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

// Sentinel errors so callers can tell "the vehicle genuinely isn't there" from
// "we couldn't reach the service to find out".
var (
	// ErrVehicleNotFound means vehicle-service answered 404 — a definitive "no".
	ErrVehicleNotFound = errors.New("client: vehicle not found")
	// ErrVehicleServiceUnavailable means we couldn't get a usable answer:
	// timeout, connection refused, or a 5xx. Treat it as "try again later".
	ErrVehicleServiceUnavailable = errors.New("client: vehicle-service unavailable")
)

const (
	requestTimeout = 3 * time.Second
	retryBackoff   = 200 * time.Millisecond
	maxAttempts    = 2
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
		http:    &http.Client{Timeout: requestTimeout},
	}
}

// GetVehicle fetches one vehicle by id. Returns ErrVehicleNotFound (404) or
// ErrVehicleServiceUnavailable (couldn't reach it).
func (c *VehicleClient) GetVehicle(ctx context.Context, id int64) (Vehicle, error) {
	var vehicle Vehicle
	if err := c.getJSON(ctx, fmt.Sprintf("/vehicles/%d", id), &vehicle); err != nil {
		return Vehicle{}, err
	}
	return vehicle, nil
}

// ListVehicles fetches every vehicle. Used by the /due calculation to get each
// vehicle's current odometer. Returns ErrVehicleServiceUnavailable if it can't
// reach the service.
func (c *VehicleClient) ListVehicles(ctx context.Context) ([]Vehicle, error) {
	var vehicles []Vehicle
	if err := c.getJSON(ctx, "/vehicles", &vehicles); err != nil {
		return nil, err
	}
	return vehicles, nil
}

// getJSON does a GET, decodes a 200 body into dest, and applies the retry
// policy: one extra attempt on a transient failure (network error or 5xx) with a
// short fixed backoff. A 404 is definitive and never retried.
func (c *VehicleClient) getJSON(ctx context.Context, path string, dest any) error {
	url := c.baseURL + path

	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		status, err := c.getOnce(ctx, url, dest)
		if err == nil {
			return nil
		}
		if status == http.StatusNotFound {
			return ErrVehicleNotFound
		}

		lastErr = err
		if attempt < maxAttempts {
			select {
			case <-time.After(retryBackoff):
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}

	// Wrap so callers can errors.Is(err, ErrVehicleServiceUnavailable) while the
	// underlying cause stays visible in logs.
	return fmt.Errorf("%w: %v", ErrVehicleServiceUnavailable, lastErr)
}

// getOnce performs a single request. It returns the HTTP status code (0 if the
// request never completed) alongside any error, so getJSON can special-case 404.
func (c *VehicleClient) getOnce(ctx context.Context, url string, dest any) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0, err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return 0, err // network-level failure: transient
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return resp.StatusCode, fmt.Errorf("vehicle-service returned status %d", resp.StatusCode)
	}

	if err := json.NewDecoder(resp.Body).Decode(dest); err != nil {
		return resp.StatusCode, fmt.Errorf("decoding vehicle-service response: %w", err)
	}
	return resp.StatusCode, nil
}
