import { findNearbyUsers } from "@/locations-service/locations-queries";
import { getCurrentStatuses, type PublicStatus } from "@/statuses-service/statuses-queries";
import { getUserProfilesByIds, type UserProfile } from "@/users-service/users-queries";

// Positions older than this are treated as unknown, so people who stopped sharing drop off.
const LOCATION_MAX_AGE_MS = 2 * 60 * 60 * 1000;
// Distances are rounded up to this, so exact positions can't be worked out from them.
const DISTANCE_STEP_METERS = 100;

export type NearbyMatch = UserProfile & { status: PublicStatus; distanceMeters: number };

export type NearbyMatches = {
  activity: PublicStatus["activity"] | null;
  matches: NearbyMatch[];
};

const roundDistance = (meters: number) =>
  Math.max(DISTANCE_STEP_METERS, Math.ceil(meters / DISTANCE_STEP_METERS) * DISTANCE_STEP_METERS);

// People within `radiusMeters` doing the same activity as the user right now, closest first.
// No activity and no matches when the user has no active status.
export async function findNearbyMatches(userId: string, radiusMeters: number): Promise<NearbyMatches> {
  const myStatus = (await getCurrentStatuses([userId])).get(userId);
  if (!myStatus) return { activity: null, matches: [] };

  const nearby = await findNearbyUsers(userId, {
    radiusMeters,
    freshSince: new Date(Date.now() - LOCATION_MAX_AGE_MS),
  });
  const statuses = await getCurrentStatuses(nearby.map((user) => user.userId));
  const matching = nearby.filter((user) => statuses.get(user.userId)?.activity.id === myStatus.activity.id);
  const profiles = new Map(
    (await getUserProfilesByIds(matching.map((user) => user.userId))).map((profile) => [profile.id, profile]),
  );

  const matches = matching.flatMap((user) => {
    const profile = profiles.get(user.userId);
    const status = statuses.get(user.userId);
    return profile && status ? [{ ...profile, status, distanceMeters: roundDistance(user.distanceMeters) }] : [];
  });
  return { activity: myStatus.activity, matches };
}
