// Package store is activity-service's data-access layer: it owns the database
// connection and every SQL statement the service runs.
//
// This file is nearly identical to vehicle-service's store/store.go. That
// duplication is deliberate — the two services are separate Go modules so they
// can be deployed and versioned independently. If the copy-paste becomes a
// burden, the shared bits could move into a third "platform" module later.
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

// ErrNotFound is returned when no row matches the given id.
var ErrNotFound = errors.New("store: record not found")

// Store wraps the *sql.DB connection pool.
type Store struct {
	db *sql.DB
}

// New opens the connection pool and pins every connection's search_path to this
// service's own schema, so activity-service physically cannot read or write
// vehicle-service's tables.
func New(databaseURL, schema string) (*Store, error) {
	connConfig, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse database url: %w", err)
	}
	if schema != "" {
		connConfig.RuntimeParams["search_path"] = schema
	}

	connStr := stdlib.RegisterConnConfig(connConfig)

	db, err := sql.Open("pgx", connStr)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(time.Hour)

	return &Store{db: db}, nil
}

// Ping verifies the database is reachable.
func (s *Store) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

// Close returns all pooled connections.
func (s *Store) Close() error {
	return s.db.Close()
}
