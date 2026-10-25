import { NEARBY_RADIUS_LABEL } from "../constants/nearby.ts";

export type NearbyAlertText = { title: string; body: string };

// The text of a nearby push alert: who's new, and how many match in all when that's more.
// `newNames` is never empty.
export function nearbyAlertText(newNames: string[], totalCount: number, activityName: string): NearbyAlertText {
  const activity = activityName.charAt(0).toLowerCase() + activityName.slice(1);
  const isOne = newNames.length === 1;

  const title = isOne ? `${newNames[0]} is nearby` : `${newNames.length} new people nearby`;
  const who =
    newNames.length === 1
      ? newNames[0]
      : newNames.length === 2
        ? `${newNames[0]} and ${newNames[1]}`
        : `${newNames[0]}, ${newNames[1]} and ${newNames.length - 2} more`;
  let body = `${who} ${isOne ? "is" : "are"} also ${activity} within ${NEARBY_RADIUS_LABEL}.`;
  if (totalCount > newNames.length) {
    body += ` ${totalCount} people nearby in all.`;
  }
  return { title, body };
}

// What other people see you called: your nickname if you have one.
export function displayName(person: { firstName: string; lastName: string; nickname: string | null }): string {
  return person.nickname ?? `${person.firstName} ${person.lastName}`;
}
