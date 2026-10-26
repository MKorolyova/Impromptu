import { refreshGoogleAccessToken } from "@/google-calendar-service/auth";
import { listGoogleCalendars, listGoogleEvents, ownCalendarIds } from "@/google-calendar-service/google-calendar";
import { getGoogleRefreshToken } from "@/google-calendar-service/google-calendar-queries";
import type { CalendarEvent } from "@/types/calendar-event";
import type { GoogleEvent, GoogleEventDateTime } from "@/types/google-event";

// Access tokens last an hour; keep them so a read every 30 seconds doesn't refresh every time.
const EXPIRY_MARGIN_MS = 60_000;
// Which calendars to read changes rarely, so the list is re-read at most this often.
const CALENDARS_TTL_MS = 15 * 60 * 1000;
const globalForTokens = globalThis as typeof globalThis & {
  googleAccessTokens?: Map<string, { token: string; expiresAt: number }>;
  googleOwnCalendars?: Map<string, { ids: string[]; fetchedAt: number }>;
};
const accessTokens = (globalForTokens.googleAccessTokens ??= new Map());
const ownCalendars = (globalForTokens.googleOwnCalendars ??= new Map());

const toIso = (time: GoogleEventDateTime) =>
  time.dateTime ? new Date(time.dateTime).toISOString() : `${time.date}T00:00:00.000Z`;

// Cancelled instances are dropped; everything else is passed through.
export function toCalendarEvent(event: GoogleEvent): CalendarEvent | null {
  if (event.status === "cancelled") return null;
  const self = event.attendees?.find((attendee) => attendee.self);
  return {
    id: event.id,
    title: event.summary ?? null,
    location: event.location ?? null,
    startAt: toIso(event.start),
    endAt: toIso(event.end),
    allDay: !event.start.dateTime,
    status: event.status,
    responseStatus: self?.responseStatus ?? null,
    hasOtherAttendees: event.attendees?.some((attendee) => !attendee.self && !attendee.resource) ?? false,
    videoCallUrl: event.hangoutLink ?? null,
    eventType: event.eventType ?? "default",
    free: event.transparency === "transparent",
  };
}

async function getAccessToken(userId: string, refreshToken: string): Promise<string> {
  const cached = accessTokens.get(userId);
  if (cached && cached.expiresAt - EXPIRY_MARGIN_MS > Date.now()) return cached.token;
  const tokens = await refreshGoogleAccessToken(refreshToken);
  accessTokens.set(userId, { token: tokens.accessToken, expiresAt: tokens.accessTokenExpiresAt.getTime() });
  return tokens.accessToken;
}

async function getOwnCalendarIds(userId: string, accessToken: string): Promise<string[]> {
  const cached = ownCalendars.get(userId);
  if (cached && Date.now() - cached.fetchedAt < CALENDARS_TTL_MS) return cached.ids;
  const ids = ownCalendarIds(await listGoogleCalendars(accessToken));
  const result = ids.length > 0 ? ids : ["primary"];
  ownCalendars.set(userId, { ids: result, fetchedAt: Date.now() });
  return result;
}

// After disconnecting or reconnecting: the cached access token and calendar list are stale.
export function forgetGoogleCalendarCache(userId: string): void {
  accessTokens.delete(userId);
  ownCalendars.delete(userId);
}

// Events on the user's own calendars (see ownCalendarIds) that end after `from` and start before `to`,
// by start time, whenever they were created. Returns null when Google Calendar isn't connected.
export async function readGoogleCalendarEvents(
  userId: string,
  from: Date,
  to: Date,
): Promise<CalendarEvent[] | null> {
  const refreshToken = await getGoogleRefreshToken(userId);
  if (!refreshToken) return null;
  const accessToken = await getAccessToken(userId, refreshToken);
  const calendarIds = await getOwnCalendarIds(userId, accessToken);

  const reads = await Promise.allSettled(
    calendarIds.map((calendarId) => listGoogleEvents(accessToken, { calendarId, timeMin: from, timeMax: to })),
  );
  const failed = reads.filter((read) => read.status === "rejected");
  // One calendar failing (removed since the list was read, say) shouldn't hide the others.
  if (failed.length === reads.length) throw failed[0].reason;
  if (failed.length > 0) ownCalendars.delete(userId);

  // An event can be on more than one of the user's calendars; keep it once.
  const byId = new Map<string, CalendarEvent>();
  for (const read of reads) {
    if (read.status !== "fulfilled") continue;
    for (const event of read.value.events.map(toCalendarEvent)) {
      if (event && !byId.has(event.id)) byId.set(event.id, event);
    }
  }
  return [...byId.values()].sort((a, b) => a.startAt.localeCompare(b.startAt));
}
