-- Milestone 3: the maintenance_entries table, in activity-service's schema.
--
-- Same "vehicle_id is a plain INT, no FK" rule as fuel_entries (architecture
-- doc 3.1).
--
-- parts_used is JSONB — a list of {name, cost} objects. JSONB stores parsed
-- JSON in a binary form Postgres can index and query into; here we only read
-- and write the whole value, so a plain column is enough.
--
-- next_due_odometer / next_due_date are the optional "remind me again at" targets
-- for this service type. Either, both, or neither may be set.

CREATE TABLE activity.maintenance_entries (
    id                SERIAL PRIMARY KEY,
    vehicle_id        INT NOT NULL,
    date              DATE NOT NULL,
    odometer          INT NOT NULL,
    service_type      TEXT NOT NULL,
    cost              NUMERIC(8,2) NOT NULL DEFAULT 0,
    parts_used        JSONB,
    notes             TEXT,
    next_due_odometer INT,
    next_due_date     DATE
);

-- The /due query is: DISTINCT ON (vehicle_id, service_type) ... ORDER BY
-- vehicle_id, service_type, date DESC, odometer DESC. An index whose leading
-- columns match that ORDER BY lets Postgres satisfy it with an index scan
-- instead of sorting the whole table.
CREATE INDEX maintenance_entries_latest_idx
    ON activity.maintenance_entries (vehicle_id, service_type, date DESC, odometer DESC);
