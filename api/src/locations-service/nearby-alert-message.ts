import { NEARBY_RADIUS_LABEL } from "../constants/nearby.ts";

export type NearbyAlertText = { title: string; body: string };

// The text of a nearby push alert, telling someone that `name` has started doing what they're doing.
export function nearbyAlertText(name: string, activityName: string): NearbyAlertText {
  const activity = activityName.charAt(0).toLowerCase() + activityName.slice(1);
  return { title: `${name} is nearby`, body: `${name} is also ${activity} within ${NEARBY_RADIUS_LABEL}.` };
}

// What the app calls other people: their nickname, or else their first name (Person.displayName).
export function displayName(person: { firstName: string; nickname: string | null }): string {
  return person.nickname ?? person.firstName;
}
