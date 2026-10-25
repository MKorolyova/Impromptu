import { refreshGoogleAccessToken } from "@/google-calendar-service/auth";
import { listGoogleEvents } from "@/google-calendar-service/google-calendar";
import { getGoogleRefreshToken } from "@/google-calendar-service/google-calendar-queries";
import type { CalendarEvent } from "@/types/calendar-event";
import type { GoogleEvent, GoogleEventDateTime } from "@/types/google-event";

// Access tokens last an hour; keep them so a read every few minutes doesn't refresh every time.
const EXPIRY_MARGIN_MS = 60_000;
const globalForTokens = globalThis as typeof globalThis & {
  googleAccessTokens?: Map<string, { token: string; expiresAt: number }>;
};
const accessTokens = (globalForTokens.googleAccessTokens ??= new Map());

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

export function forgetGoogleAccessToken(userId: string): void {
  accessTokens.delete(userId);
}

// Events on the user's primary calendar that end after `from` and start before `to`, by start time.
// Returns null when Google Calendar isn't connected.
export async function readGoogleCalendarEvents(
  userId: string,
  from: Date,
  to: Date,
): Promise<CalendarEvent[] | null> {
  const refreshToken = await getGoogleRefreshToken(userId);
  if (!refreshToken) return null;
  const accessToken = await getAccessToken(userId, refreshToken);
  const { events } = await listGoogleEvents(accessToken, { timeMin: from, timeMax: to });
  return events.map(toCalendarEvent).filter((event): event is CalendarEvent => event !== null);
}
