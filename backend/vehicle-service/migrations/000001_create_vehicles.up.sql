-- Milestone 1: the vehicles table.
--
-- This runs with search_path = vehicle (set in scripts/migrate.sh and
-- docker-compose.yml), but we qualify the name explicitly so it's unambiguous
-- when reading the file on its own.
--
-- Column choices come straight from docs/Dipstick_Architecture.md section 3.
-- SERIAL = "auto-incrementing integer" (Postgres creates a hidden sequence and
-- makes this column default to its next value).

CREATE TABLE vehicle.vehicles (
    id               SERIAL PRIMARY KEY,
    name             TEXT NOT NULL,
    year             INT,
    make             TEXT,
    model            TEXT,
    vin              TEXT,
    current_odometer INT NOT NULL DEFAULT 0
);
