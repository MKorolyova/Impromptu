import { NEARBY_RADIUS_METERS } from "@/constants/nearby";
import { db } from "@/db/index";
import { nearbyAlerts } from "@/db/schema";
import { findNearbyMatches } from "@/locations-service/nearby";
import { displayName, nearbyAlertText } from "@/locations-service/nearby-alert-message";
import { pushToUsers } from "@/push-service/push";
import { getUserProfilesByIds } from "@/users-service/users-queries";

// The app screen a nearby alert opens (AppRoute.nearbyPeople).
const NEARBY_ROUTE = "nearbyPeople";

type NearbyAlert = { recipientStatusId: string; otherUserId: string };

// Saves the alerts and returns the ones that weren't saved before.
async function recordNearbyAlerts(alerts: NearbyAlert[]): Promise<NearbyAlert[]> {
  if (alerts.length === 0) return [];
  return db
    .insert(nearbyAlerts)
    .values(alerts)
    .onConflictDoNothing()
    .returning({ recipientStatusId: nearbyAlerts.recipientStatusId, otherUserId: nearbyAlerts.otherUserId });
}

// After the user sets a status or reports a position: everyone within 3 miles already doing the same
// thing gets a push that the user is too. The user gets nothing; the people who were already there aren't
// news to them, and they're recorded so a later position report from one of them doesn't announce them.
// Each person hears about someone once per status of theirs, so the user updating their status (or
// reporting again) doesn't repeat it.
export async function announceNearbyMatches(userId: string): Promise<void> {
  const { status, matches } = await findNearbyMatches(userId, NEARBY_RADIUS_METERS);
  if (!status || matches.length === 0) return;

  await recordNearbyAlerts(matches.map((match) => ({ recipientStatusId: status.id, otherUserId: match.id })));
  // Recorded before sending, so two checks at once can't both announce the user.
  const newlyTold = await recordNearbyAlerts(
    matches.map((match) => ({ recipientStatusId: match.status.id, otherUserId: userId })),
  );
  if (newlyTold.length === 0) return;
  const [me] = await getUserProfilesByIds([userId]);
  if (!me) return;

  const toldStatusIds = new Set(newlyTold.map((alert) => alert.recipientStatusId));
  const message = { ...nearbyAlertText(displayName(me), status.activity.name), route: NEARBY_ROUTE };
  await pushToUsers(
    matches.filter((match) => toldStatusIds.has(match.status.id)).map((match) => ({ userId: match.id, message })),
  );
}

// For route handlers and jobs: announces in the background, so the caller doesn't wait for APNs.
export function announceNearbyMatchesLater(userId: string): void {
  announceNearbyMatches(userId).catch((error: unknown) =>
    console.error(`Nearby alerts failed: ${error instanceof Error ? error.message : String(error)}`),
  );
}
