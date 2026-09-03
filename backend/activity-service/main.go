// Command activity-service is the HTTP API that owns fuel entries (and, from
// Milestone 3, maintenance entries) for Dipstick. It computes MPG and calls
// vehicle-service over HTTP when it needs vehicle data.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/colinfriedel/dipstick/activity-service/client"
	"github.com/colinfriedel/dipstick/activity-service/handlers"
	"github.com/colinfriedel/dipstick/activity-service/reconcile"
	"github.com/colinfriedel/dipstick/activity-service/service"
	"github.com/colinfriedel/dipstick/activity-service/store"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	// --- Configuration ---
	port := getenv("PORT", "8080")
	schema := getenv("DB_SCHEMA", "activity")

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return errors.New("DATABASE_URL is required")
	}

	vehicleServiceURL := os.Getenv("VEHICLE_SERVICE_URL")
	if vehicleServiceURL == "" {
		return errors.New("VEHICLE_SERVICE_URL is required")
	}

	// The "due soon" buffers are tunable per the spec; default to 500 mi / 14 days.
	dueConfig := service.DefaultDueConfig()
	dueConfig.MilesBuffer = getenvInt("DUE_MILES_BUFFER", dueConfig.MilesBuffer)
	dueConfig.DaysBuffer = getenvInt("DUE_DAYS_BUFFER", dueConfig.DaysBuffer)

	cacheTTL := getenvDuration("VEHICLE_CACHE_TTL", 30*time.Second)
	reconcileInterval := getenvDuration("RECONCILE_INTERVAL", time.Hour)

	// --- Dependencies ---
	st, err := store.New(databaseURL, schema)
	if err != nil {
		return err
	}
	defer st.Close()

	// We wait for our own database, but deliberately NOT for vehicle-service.
	// If vehicle-service is down, creating a fuel entry returns 503 and reads
	// still work — that's handled at request time, not startup.
	if err := waitForDatabase(st, 30, 2*time.Second); err != nil {
		return err
	}
	log.Println("connected to database")

	// The raw client talks to vehicle-service directly. The caching client wraps
	// it for the HTTP handlers (fewer round trips, rides out brief blips). The
	// reconciler gets the *raw* client on purpose — it makes delete decisions
	// and wants ground truth, not a possibly-stale cache.
	vehicleClient := client.NewVehicleClient(vehicleServiceURL)
	cachedVehicleClient := client.NewCachingVehicleClient(vehicleClient, cacheTTL)

	log.Printf("vehicle-service base URL: %s", vehicleServiceURL)
	log.Printf("due buffers: %d miles, %d days", dueConfig.MilesBuffer, dueConfig.DaysBuffer)
	log.Printf("vehicle cache TTL: %s | reconcile interval: %s", cacheTTL, reconcileInterval)

	// --- HTTP server ---
	server := &http.Server{
		Addr: ":" + port,
		Handler: handlers.NewRouter(handlers.Deps{
			Fuel:        st,
			Maintenance: st,
			Vehicles:    cachedVehicleClient,
			DueConfig:   dueConfig,
		}),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// --- Background orphan reconciler ---
	// Launched in its own goroutine, tied to ctx so it stops on shutdown. The
	// WaitGroup lets run() wait for it to finish its current pass before returning.
	var workers sync.WaitGroup
	if reconcileInterval > 0 {
		reconciler := reconcile.New(st, vehicleClient, reconcileInterval)
		workers.Add(1)
		go func() {
			defer workers.Done()
			reconciler.Run(ctx)
		}()
	} else {
		log.Println("orphan reconciler disabled (RECONCILE_INTERVAL <= 0)")
	}

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("activity-service listening on %s", server.Addr)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErrors:
		return fmt.Errorf("server failed to start: %w", err)
	case <-ctx.Done():
		log.Println("shutdown signal received")
	}

	// Graceful shutdown: stop accepting requests, drain in-flight ones, then
	// wait for the background worker (already unblocking on the cancelled ctx).
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("graceful shutdown failed: %w", err)
	}
	workers.Wait()
	log.Println("shutdown complete")
	return nil
}

func waitForDatabase(st *store.Store, attempts int, delay time.Duration) error {
	for attempt := 1; attempt <= attempts; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		err := st.Ping(ctx)
		cancel()
		if err == nil {
			return nil
		}
		log.Printf("waiting for database (attempt %d/%d): %v", attempt, attempts, err)
		time.Sleep(delay)
	}
	return fmt.Errorf("database not reachable after %d attempts", attempts)
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// getenvInt reads an integer environment variable, falling back to the default
// when unset or unparseable.
func getenvInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		log.Printf("ignoring %s=%q: not an integer", key, value)
		return fallback
	}
	return parsed
}

// getenvDuration reads a Go duration string ("30s", "1h", "0" to disable),
// falling back to the default when unset or unparseable.
func getenvDuration(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		log.Printf("ignoring %s=%q: not a duration", key, value)
		return fallback
	}
	return parsed
}
