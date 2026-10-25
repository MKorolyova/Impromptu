import { and, eq, gt, ne, sql, type Column } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { db } from "@/db/index";
import { userLocations } from "@/db/schema";
import type { UpdateLocationRequest } from "@/validators/locations";

// Replaces the user's last known position.
export async function upsertUserLocation(userId: string, input: UpdateLocationRequest): Promise<void> {
  const values = {
    geom: { x: input.longitude, y: input.latitude },
    accuracyMeters: input.accuracyMeters == null ? null : Math.round(input.accuracyMeters),
  };
  await db
    .insert(userLocations)
    .values({ userId, ...values })
    .onConflictDoUpdate({ target: userLocations.userId, set: { ...values, updatedAt: new Date() } });
}

// Returns false when the user wasn't sharing a location.
export async function deleteUserLocation(userId: string): Promise<boolean> {
  const deleted = await db
    .delete(userLocations)
    .where(eq(userLocations.userId, userId))
    .returning({ userId: userLocations.userId });
  return deleted.length > 0;
}

// People whose position, reported after `freshSince`, is within `radiusMeters` of the user's own.
// Empty when the user's own position is missing or older than `freshSince`.
export async function findNearbyUserIds(
  userId: string,
  { radiusMeters, freshSince }: { radiusMeters: number; freshSince: Date },
): Promise<string[]> {
  const me = alias(userLocations, "me");
  // Points are stored as lon/lat; geography measures in meters on the globe.
  const asGeography = (geom: Column) => sql`ST_SetSRID(${geom}, 4326)::geography`;
  const rows = await db
    .select({ userId: userLocations.userId })
    .from(userLocations)
    .innerJoin(me, and(eq(me.userId, userId), gt(me.updatedAt, freshSince)))
    .where(
      and(
        ne(userLocations.userId, userId),
        gt(userLocations.updatedAt, freshSince),
        sql`ST_DWithin(${asGeography(userLocations.geom)}, ${asGeography(me.geom)}, ${radiusMeters})`,
      ),
    );
  return rows.map((row) => row.userId);
}
