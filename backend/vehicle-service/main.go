// Command vehicle-service is the HTTP API that owns Vehicle records for Dipstick.
//
// This file is the composition root: it reads configuration from the
// environment, builds the store and the router, and manages the process
// lifecycle (start listening, then shut down cleanly on a signal).
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/colinfriedel/dipstick/vehicle-service/handlers"
	"github.com/colinfriedel/dipstick/vehicle-service/store"
)

func main() {
	// The real work is in run() so it can return an error. main() just decides
	// what to do with it. log.Fatal prints and exits with status 1.
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	// --- Configuration from the environment ---
	// 12-factor style: config comes from env vars, not a checked-in file. In
	// local dev these are set by docker-compose.yml; in production by the host.
	port := getenv("PORT", "8080")
	schema := getenv("DB_SCHEMA", "vehicle")
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return errors.New("DATABASE_URL is required")
	}

	// --- Data layer ---
	st, err := store.New(databaseURL, schema)
	if err != nil {
		return err
	}
	defer st.Close()

	// Postgres may not accept connections the instant this process starts
	// (especially under Compose). Retry the first connection for a while.
	if err := waitForDatabase(st, 30, 2*time.Second); err != nil {
		return err
	}
	log.Println("connected to database")

	// --- HTTP server ---
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      handlers.NewRouter(st),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// signal.NotifyContext gives us a context that is cancelled when the process
	// receives SIGINT (Ctrl-C) or SIGTERM (what `docker stop` sends).
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// ListenAndServe blocks, so it runs in its own goroutine. When we later call
	// server.Shutdown, ListenAndServe returns http.ErrServerClosed, which is the
	// normal, expected outcome — not a real error.
	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("vehicle-service listening on %s", server.Addr)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErrors:
		return fmt.Errorf("server failed to start: %w", err)

	case <-ctx.Done():
		log.Println("shutdown signal received")

		// Give in-flight requests up to 10s to finish before forcing the close.
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("graceful shutdown failed: %w", err)
		}
		log.Println("shutdown complete")
		return nil
	}
}

// waitForDatabase pings the database until it responds or we run out of attempts.
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

// getenv reads an environment variable, falling back to a default when unset.
func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
