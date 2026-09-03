package client

import (
	"context"
	"errors"
	"log"
	"sync"
	"time"
)

// CachingVehicleClient wraps a VehicleFetcher and remembers recent answers for a
// short time. It satisfies the same method set as the thing it wraps (the
// "decorator" pattern), so callers can't tell the difference — they just get
// fewer network round trips.
//
// Two jobs:
//   - Skip the network for repeated lookups within the TTL (a burst of fuel-entry
//     creates for one vehicle, or rapid /due polling).
//   - Ride out a brief vehicle-service outage: if the upstream call fails with a
//     transient error and we have a not-too-old cached value, serve that instead
//     of failing.
type CachingVehicleClient struct {
	inner VehicleFetcher
	ttl   time.Duration

	// staleGrace is how far past the TTL a cached value may still be served,
	// but only when the upstream is failing transiently.
	staleGrace time.Duration

	// now is injectable so tests can control time without sleeping.
	now func() time.Time

	mu     sync.RWMutex
	byID   map[int64]cachedVehicle
	list   []Vehicle
	listAt time.Time
}

// VehicleFetcher is the behavior CachingVehicleClient wraps. *VehicleClient
// satisfies it, and so does CachingVehicleClient itself.
type VehicleFetcher interface {
	GetVehicle(ctx context.Context, id int64) (Vehicle, error)
	ListVehicles(ctx context.Context) ([]Vehicle, error)
}

type cachedVehicle struct {
	vehicle   Vehicle
	fetchedAt time.Time
}

// NewCachingVehicleClient wraps inner with a cache of the given TTL. A ttl <= 0
// disables caching entirely — every call passes straight through.
func NewCachingVehicleClient(inner VehicleFetcher, ttl time.Duration) *CachingVehicleClient {
	return &CachingVehicleClient{
		inner:      inner,
		ttl:        ttl,
		staleGrace: ttl, // serve values up to 2*ttl old while the upstream is down
		now:        time.Now,
		byID:       make(map[int64]cachedVehicle),
	}
}

// GetVehicle returns a cached vehicle when one is fresh, otherwise fetches and
// caches. On a transient upstream failure it falls back to a recent stale value.
func (c *CachingVehicleClient) GetVehicle(ctx context.Context, id int64) (Vehicle, error) {
	if c.ttl <= 0 {
		return c.inner.GetVehicle(ctx, id)
	}

	now := c.now()

	c.mu.RLock()
	entry, cached := c.byID[id]
	c.mu.RUnlock()

	if cached && now.Sub(entry.fetchedAt) < c.ttl {
		return entry.vehicle, nil
	}

	vehicle, err := c.inner.GetVehicle(ctx, id)
	if err == nil {
		c.mu.Lock()
		c.byID[id] = cachedVehicle{vehicle: vehicle, fetchedAt: now}
		c.mu.Unlock()
		return vehicle, nil
	}

	if cached && errors.Is(err, ErrVehicleServiceUnavailable) &&
		now.Sub(entry.fetchedAt) < c.ttl+c.staleGrace {
		log.Printf("client: vehicle-service unavailable, serving stale vehicle %d (age %s)",
			id, now.Sub(entry.fetchedAt).Round(time.Second))
		return entry.vehicle, nil
	}

	return Vehicle{}, err
}

// ListVehicles caches the whole fleet list. A successful fetch also warms the
// per-id cache, so a /due call makes later single lookups free.
func (c *CachingVehicleClient) ListVehicles(ctx context.Context) ([]Vehicle, error) {
	if c.ttl <= 0 {
		return c.inner.ListVehicles(ctx)
	}

	now := c.now()

	c.mu.RLock()
	cachedList, cachedAt := c.list, c.listAt
	c.mu.RUnlock()

	if cachedList != nil && now.Sub(cachedAt) < c.ttl {
		return cachedList, nil
	}

	vehicles, err := c.inner.ListVehicles(ctx)
	if err == nil {
		c.mu.Lock()
		c.list = vehicles
		c.listAt = now
		for _, v := range vehicles {
			c.byID[v.ID] = cachedVehicle{vehicle: v, fetchedAt: now}
		}
		c.mu.Unlock()
		return vehicles, nil
	}

	if cachedList != nil && errors.Is(err, ErrVehicleServiceUnavailable) &&
		now.Sub(cachedAt) < c.ttl+c.staleGrace {
		log.Printf("client: vehicle-service unavailable, serving stale vehicle list (age %s)",
			now.Sub(cachedAt).Round(time.Second))
		return cachedList, nil
	}

	return nil, err
}
