-- Reverses 000001_create_vehicles.up.sql. golang-migrate runs this when you
-- migrate "down" one step. Every up migration should have a matching down so a
-- bad migration can be rolled back cleanly.

DROP TABLE IF EXISTS vehicle.vehicles;
