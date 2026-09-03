package client

import (
	"context"
	"sync"
	"testing"
	"time"
)

// countingFetcher records how many times each method was called and lets a test
// dictate what it returns.
type countingFetcher struct {
	mu        sync.Mutex
	getCalls  int
	listCalls int

	vehicle Vehicle
	list    []Vehicle
	err     error
}

func (f *countingFetcher) GetVehicle(ctx context.Context, id int64) (Vehicle, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.getCalls++
	if f.err != nil {
		return Vehicle{}, f.err
	}
	return f.vehicle, nil
}

func (f *countingFetcher) ListVehicles(ctx context.Context) ([]Vehicle, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.listCalls++
	if f.err != nil {
		return nil, f.err
	}
	return f.list, nil
}

func TestCache_HitWithinTTL(t *testing.T) {
	fake := &countingFetcher{vehicle: Vehicle{ID: 1, Name: "Car"}}
	clock := time.Now()
	c := NewCachingVehicleClient(fake, time.Minute)
	c.now = func() time.Time { return clock }

	for i := 0; i < 3; i++ {
		if _, err := c.GetVehicle(context.Background(), 1); err != nil {
			t.Fatalf("call %d: %v", i, err)
		}
	}
	if fake.getCalls != 1 {
		t.Fatalf("upstream called %d times, want 1 (rest served from cache)", fake.getCalls)
	}
}

func TestCache_RefetchesAfterTTL(t *testing.T) {
	fake := &countingFetcher{vehicle: Vehicle{ID: 1}}
	clock := time.Now()
	c := NewCachingVehicleClient(fake, time.Minute)
	c.now = func() time.Time { return clock }

	c.GetVehicle(context.Background(), 1)
	clock = clock.Add(2 * time.Minute) // TTL expired
	c.GetVehicle(context.Background(), 1)

	if fake.getCalls != 2 {
		t.Fatalf("upstream called %d times, want 2", fake.getCalls)
	}
}

func TestCache_ServesStaleOnTransientError(t *testing.T) {
	fake := &countingFetcher{vehicle: Vehicle{ID: 1, Name: "Cached Car"}}
	clock := time.Now()
	c := NewCachingVehicleClient(fake, time.Minute)
	c.now = func() time.Time { return clock }

	// Prime the cache.
	if _, err := c.GetVehicle(context.Background(), 1); err != nil {
		t.Fatal(err)
	}

	// Upstream goes down; entry is now stale (past TTL) but within the grace window.
	fake.err = ErrVehicleServiceUnavailable
	clock = clock.Add(90 * time.Second) // ttl=60s, grace=60s -> still inside 120s

	got, err := c.GetVehicle(context.Background(), 1)
	if err != nil {
		t.Fatalf("expected stale value, got error: %v", err)
	}
	if got.Name != "Cached Car" {
		t.Fatalf("got %q, want the cached value", got.Name)
	}
}

func TestCache_ErrorsWhenStaleValueTooOld(t *testing.T) {
	fake := &countingFetcher{vehicle: Vehicle{ID: 1}}
	clock := time.Now()
	c := NewCachingVehicleClient(fake, time.Minute)
	c.now = func() time.Time { return clock }

	c.GetVehicle(context.Background(), 1)

	fake.err = ErrVehicleServiceUnavailable
	clock = clock.Add(5 * time.Minute) // well past ttl + grace

	if _, err := c.GetVehicle(context.Background(), 1); err == nil {
		t.Fatal("expected an error once the cached value is too old to trust")
	}
}

func TestCache_Disabled(t *testing.T) {
	fake := &countingFetcher{vehicle: Vehicle{ID: 1}}
	c := NewCachingVehicleClient(fake, 0) // disabled

	c.GetVehicle(context.Background(), 1)
	c.GetVehicle(context.Background(), 1)

	if fake.getCalls != 2 {
		t.Fatalf("upstream called %d times, want 2 (cache disabled)", fake.getCalls)
	}
}

func TestCache_ListWarmsPerIDCache(t *testing.T) {
	fake := &countingFetcher{list: []Vehicle{{ID: 1}, {ID: 2}}}
	clock := time.Now()
	c := NewCachingVehicleClient(fake, time.Minute)
	c.now = func() time.Time { return clock }

	if _, err := c.ListVehicles(context.Background()); err != nil {
		t.Fatal(err)
	}
	// Both vehicles should now be individually cached.
	if _, err := c.GetVehicle(context.Background(), 2); err != nil {
		t.Fatal(err)
	}
	if fake.getCalls != 0 {
		t.Fatalf("GetVehicle hit the upstream %d times, want 0 (warmed by the list)", fake.getCalls)
	}
}
