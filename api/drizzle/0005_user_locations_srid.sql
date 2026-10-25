-- 0004 was first generated without the SRID (drizzle-kit drops it). Databases that ran that version
-- have user_locations.geom with no SRID; this sets it to 4326 like places.geom. No-op where it's already 4326.
ALTER TABLE "user_locations" ALTER COLUMN "geom" TYPE geometry(point, 4326) USING ST_SetSRID("geom", 4326);
