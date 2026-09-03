-- Milestone 2: the fuel_entries table, in activity-service's own schema.
--
-- vehicle_id is a plain INT with NO foreign key to vehicle.vehicles (see
-- docs/Dipstick_Architecture.md section 3.1). activity-service validates the
-- vehicle by calling vehicle-service's HTTP API, not by joining across schemas.
--
-- NUMERIC(p, s) is exact decimal: NUMERIC(6,3) holds up to 999.999 (6 digits,
-- 3 after the point) for gallons; NUMERIC(8,2) holds up to 999999.99 for cost.

CREATE TABLE activity.fuel_entries (
    id           SERIAL PRIMARY KEY,
    vehicle_id   INT NOT NULL,
    date         DATE NOT NULL,
    odometer     INT NOT NULL,
    gallons      NUMERIC(6,3) NOT NULL,
    total_cost   NUMERIC(8,2) NOT NULL,
    is_full_tank BOOLEAN NOT NULL DEFAULT TRUE,
    station_name TEXT,
    notes        TEXT
);

-- Every query filters by vehicle_id and orders by odometer (the MPG pass and the
-- history list both do). A composite index serves the filter and the sort in one
-- structure.
CREATE INDEX fuel_entries_vehicle_odometer_idx
    ON activity.fuel_entries (vehicle_id, odometer);
