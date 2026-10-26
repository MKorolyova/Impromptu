import { ensureStandardActivities } from "@/activities-service/activities-queries";
import { classifyCalendarEvent } from "@/ai-service/classify-calendar-event";
import { ACTIVITIES } from "@/constants/activities";
import {
  deleteGoogleCalendarLink,
  listGoogleCalendarUsers,
  type GoogleCalendarUser,
} from "@/google-calendar-service/google-calendar-queries";
import { GoogleApiError } from "@/google-calendar-service/google-request";
import { forgetGoogleCalendarCache, readGoogleCalendarEvents } from "@/google-calendar-service/read-google-calendar";
import { announceNearbyMatchesLater } from "@/locations-service/nearby-alerts";
import {
  createCalendarStatus,
  hasCalendarStatus,
  listActiveCalendarStatuses,
  softDeleteStatus,
  updateStatusExpiresAt,
} from "@/statuses-service/statuses-queries";
import type { CalendarEvent } from "@/types/calendar-event";
import { endOfLocalDay, localDateKey } from "@/utils/time-zone";

// While Gemini is rate limited, keep retrying on each run for this long, then use the fallback rule.
const WAIT_FOR_GEMINI_MS = 5 * 60 * 1000;
const SKIPPED_EVENT_TYPES = new Set(["outOfOffice", "workingLocation", "birthday"]);

// Event starts already turned into statuses (or given up on) today, so Gemini isn't asked twice.
// In memory only; after a restart, hasCalendarStatus keeps statuses from being made again.
type TodaySchedule = { dayKey: string; handled: Set<string> };

// On globalThis so API routes and the background job share it, and it survives dev reloads.
const globalForCalendar = globalThis as typeof globalThis & {
  calendarSchedules?: Map<string, TodaySchedule>;
  calendarTickRunning?: boolean;
};
const schedules = (globalForCalendar.calendarSchedules ??= new Map());

export type CalendarCheckResult = { eventsToday: number; statusesStarted: number };

// Whether an event should become a status when it starts.
export function becomesStatus(event: CalendarEvent): boolean {
  return (
    !event.allDay &&
    !event.free &&
    event.responseStatus !== "declined" &&
    !SKIPPED_EVENT_TYPES.has(event.eventType) &&
    new Date(event.endAt) > new Date(event.startAt)
  );
}

const eventStartKey = (event: CalendarEvent) => `${event.id}|${event.startAt}`;

export function readTodayGoogleCalendarEvents(user: GoogleCalendarUser, now = new Date()) {
  return readGoogleCalendarEvents(user.userId, now, endOfLocalDay(user.timeZone, now));
}

// Keeps statuses already created in step with their events: a cancelled, declined or moved
// event removes its status, and a new end time moves expiresAt.
async function reconcileActiveStatuses(userId: string, events: CalendarEvent[], now: Date): Promise<void> {
  const eventsById = new Map(events.map((event) => [event.id, event]));
  for (const status of await listActiveCalendarStatuses(userId, now)) {
    const event = eventsById.get(status.googleEventId);
    if (!event || !becomesStatus(event) || new Date(event.startAt).getTime() !== status.startedAt.getTime()) {
      await softDeleteStatus(userId, status.id);
      continue;
    }
    const endAt = new Date(event.endAt);
    if (endAt.getTime() !== status.expiresAt.getTime()) await updateStatusExpiresAt(status.id, endAt);
  }
}

// Classifies a started event with Gemini and saves it as a CALENDAR status with the event's times.
async function startStatusForEvent(
  user: GoogleCalendarUser,
  event: CalendarEvent,
  schedule: TodaySchedule,
): Promise<boolean> {
  const key = eventStartKey(event);
  if (schedule.handled.has(key)) return false;

  const startedAt = new Date(event.startAt);
  if (await hasCalendarStatus(user.userId, event.id, startedAt)) {
    schedule.handled.add(key);
    return false;
  }

  const waitIfRateLimited = Date.now() - startedAt.getTime() < WAIT_FOR_GEMINI_MS;
  const classification = await classifyCalendarEvent(event, user.timeZone, { waitIfRateLimited });
  // Rate limited: leave it unhandled so the next run tries again.
  if (!classification) return false;
  const { activityName } = classification;
  const definition = ACTIVITIES.find((activity) => activity.name === activityName);
  // The activity's row is made the first time anyone uses it, so this doesn't depend on db:seed.
  const [activityId] = definition ? await ensureStandardActivities([definition]) : [];
  if (!activityId) {
    schedule.handled.add(key);
    console.error(`Calendar classification picked "${activityName}", which isn't a standard activity`);
    return false;
  }

  const status = await createCalendarStatus({
    userId: user.userId,
    activityId,
    googleEventId: event.id,
    startedAt,
    expiresAt: new Date(event.endAt),
  });
  schedule.handled.add(key);
  if (status) announceNearbyMatchesLater(user.userId);
  return status !== null;
}

// Reads the rest of today from Google, every event whenever it was created, so events added, moved or
// cancelled count by the next run, 30 seconds later. Keeps existing calendar statuses in step, then turns every
// event that has started and not ended into a status. Returns null when Google isn't connected.
export async function checkGoogleCalendar(user: GoogleCalendarUser): Promise<CalendarCheckResult | null> {
  const now = new Date();
  const events = await readTodayGoogleCalendarEvents(user, now);
  if (!events) {
    schedules.delete(user.userId);
    return null;
  }
  const dayKey = localDateKey(user.timeZone, now);
  const previous = schedules.get(user.userId);
  const schedule: TodaySchedule = previous?.dayKey === dayKey ? previous : { dayKey, handled: new Set() };
  schedules.set(user.userId, schedule);
  await reconcileActiveStatuses(user.userId, events, now);

  let statusesStarted = 0;
  for (const event of events) {
    if (!becomesStatus(event)) continue;
    if (new Date(event.startAt) > now || new Date(event.endAt) <= now) continue;
    if (await startStatusForEvent(user, event, schedule)) statusesStarted++;
  }
  return { eventsToday: events.length, statusesStarted };
}

export function forgetGoogleCalendarUser(userId: string): void {
  schedules.delete(userId);
  forgetGoogleCalendarCache(userId);
}

// Runs every 30 seconds: checks every connected user. One failing user doesn't stop the rest. A run that
// takes longer than that is never overlapped by the next one.
export async function runGoogleCalendarTick(): Promise<void> {
  if (globalForCalendar.calendarTickRunning) return;
  globalForCalendar.calendarTickRunning = true;
  try {
    const users = await listGoogleCalendarUsers();
    const connected = new Set(users.map((user) => user.userId));
    for (const userId of schedules.keys()) if (!connected.has(userId)) forgetGoogleCalendarUser(userId);

    for (const user of users) {
      try {
        await checkGoogleCalendar(user);
      } catch (error) {
        if (error instanceof GoogleApiError && error.isInvalidGrant) {
          // The user revoked access in Google; they have to connect again.
          await deleteGoogleCalendarLink(user.userId);
          forgetGoogleCalendarUser(user.userId);
          continue;
        }
        console.error(`Google Calendar check failed for user ${user.userId}: ${(error as Error).message}`);
      }
    }
  } finally {
    globalForCalendar.calendarTickRunning = false;
  }
}
