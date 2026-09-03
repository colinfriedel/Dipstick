// Package store is the data-access layer: it owns the database connection and
// every SQL statement the service runs. Handlers and business logic call into
// this package and never touch database/sql directly. Keeping SQL in one place
// makes it easy to see the full surface area of what the service does to the DB.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
)

// ErrNotFound is returned by the read/update/delete methods when no row matches
// the given id. Handlers check for this to decide between a 404 and a 500.
var ErrNotFound = errors.New("store: record not found")

// Store wraps a *sql.DB. sql.DB is not a single connection — it's a pool of
// connections that database/sql opens, reuses, and closes as needed. It is safe
// for concurrent use, so we create one and share it for the whole process.
type Store struct {
	db *sql.DB
}

// New opens the connection pool.
//
// database/sql is Go's standard database abstraction. It doesn't know how to
// speak any specific database's wire protocol — that's the job of a *driver*.
// We import github.com/jackc/pgx/v5/stdlib for its side effect: its init()
// registers a driver named "pgx" with database/sql. sql.Open("pgx", ...) then
// hands us a pool that talks Postgres.
//
// We set search_path as a connection runtime parameter so every connection in
// the pool only sees this service's schema. Postgres sends this at connection
// startup, so it's applied consistently no matter which pooled connection a
// query lands on.
func New(databaseURL, schema string) (*Store, error) {
	connConfig, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse database url: %w", err)
	}
	if schema != "" {
		connConfig.RuntimeParams["search_path"] = schema
	}

	// RegisterConnConfig stashes the parsed config and returns an opaque string
	// to hand to sql.Open in place of a DSN.
	connStr := stdlib.RegisterConnConfig(connConfig)

	db, err := sql.Open("pgx", connStr)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	// Pool tuning. Small numbers are fine for a single-user app; the point is
	// that these knobs exist. MaxOpenConns caps total connections to Postgres.
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(time.Hour)

	return &Store{db: db}, nil
}

// Ping checks that the database is actually reachable. sql.Open above does no
// real network I/O — the first connection is made lazily — so this is how we
// verify connectivity at startup.
func (s *Store) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

// Close returns all pooled connections. Called once on shutdown.
func (s *Store) Close() error {
	return s.db.Close()
}
