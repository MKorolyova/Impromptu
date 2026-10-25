import { NEARBY_RADIUS_METERS } from "@/constants/nearby";
import { db } from "@/db/index";
import { nearbyAlerts } from "@/db/schema";
import { findNearbyMatches } from "@/locations-service/nearby";
import { displayName, nearbyAlertText } from "@/locations-service/nearby-alert-message";
import { pushToUsers } from "@/push-service/push";
import type { PushMessage } from "@/push-service/apns-protocol";
import { getUserProfilesByIds } from "@/users-service/users-queries";

// The app screen a nearby alert opens (AppRoute.nearbyPeople).
const NEARBY_ROUTE = "nearbyPeople";

type NearbyAlert = { recipientId: string; statusId: string };

// Saves the alerts and returns the ones that weren't saved before: those are the ones to send.
async function recordNearbyAlerts(alerts: NearbyAlert[]): Promise<NearbyAlert[]> {
  if (alerts.length === 0) return [];
  return db
    .insert(nearbyAlerts)
    .values(alerts)
    .onConflictDoNothing()
    .returning({ recipientId: nearbyAlerts.recipientId, statusId: nearbyAlerts.statusId });
}

// Pushes "someone nearby is doing the same thing" both ways between the user and everyone within
// 3 miles who shares their activity: each of them hears about the user, and the user hears about
// all of them in one notification. Each person is told about each status once, so calling this again
// (after the next position report, say) only announces new matches.
export async function announceNearbyMatches(userId: string): Promise<void> {
  const { status, matches } = await findNearbyMatches(userId, NEARBY_RADIUS_METERS);
  if (!status || matches.length === 0) return;

  // Recorded before sending, so two checks at once can't both announce the same match.
  const recorded = await recordNearbyAlerts([
    ...matches.map((match) => ({ recipientId: match.id, statusId: status.id })),
    ...matches.map((match) => ({ recipientId: userId, statusId: match.status.id })),
  ]);
  const isNew = new Set(recorded.map(({ recipientId, statusId }) => `${recipientId}:${statusId}`));
  const [me] = await getUserProfilesByIds([userId]);
  if (!me) return;

  const message = (newNames: string[], totalCount: number): PushMessage => ({
    ...nearbyAlertText(newNames, totalCount, status.activity.name),
    route: NEARBY_ROUTE,
  });
  const messages = matches
    .filter((match) => isNew.has(`${match.id}:${status.id}`))
    .map((match) => ({ userId: match.id, message: message([displayName(me)], 1) }));
  const newForMe = matches.filter((match) => isNew.has(`${userId}:${match.status.id}`));
  if (newForMe.length > 0) {
    messages.push({ userId, message: message(newForMe.map(displayName), matches.length) });
  }
  await pushToUsers(messages);
}

// For route handlers and jobs: announces in the background, so the caller doesn't wait for APNs.
export function announceNearbyMatchesLater(userId: string): void {
  announceNearbyMatches(userId).catch((error: unknown) =>
    console.error(`Nearby alerts failed: ${error instanceof Error ? error.message : String(error)}`),
  );
}
