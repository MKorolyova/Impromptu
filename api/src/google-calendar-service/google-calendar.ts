import { googleRequest } from "@/google-calendar-service/google-request";
import type { GoogleCalendarList, GoogleCalendarListEntry } from "@/types/google-calendar";
import type { GoogleChannel, WatchGoogleEventsInput } from "@/types/google-channel";
import type { GoogleEvent, GoogleEventList, ListGoogleEventsInput, ListGoogleEventsResult } from "@/types/google-event";
import type { GoogleFreeBusyResponse, GoogleTimePeriod } from "@/types/google-free-busy";

const CALENDAR_API_URL = "https://www.googleapis.com/calendar/v3";
const PRIMARY_CALENDAR = "primary";

function calendarUrl(path: string, params: Record<string, string | undefined> = {}): URL {
  const url = new URL(`${CALENDAR_API_URL}${path}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, value);
  }
  return url;
}

function authHeaders(accessToken: string): HeadersInit {
  return { Authorization: `Bearer ${accessToken}` };
}

function postJson<T>(accessToken: string, url: URL, body: unknown): Promise<T> {
  return googleRequest<T>(url, {
    method: "POST",
    headers: { ...authHeaders(accessToken), "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

export async function listGoogleCalendars(accessToken: string): Promise<GoogleCalendarListEntry[]> {
  const calendars: GoogleCalendarListEntry[] = [];
  let pageToken: string | undefined;
  do {
    const page = await googleRequest<GoogleCalendarList>(
      calendarUrl("/users/me/calendarList", { pageToken }),
      { headers: authHeaders(accessToken) },
    );
    calendars.push(...page.items);
    pageToken = page.nextPageToken;
  } while (pageToken);
  return calendars;
}

// The calendars whose events are the user's own plans: their primary calendar, plus any other calendar
// they own and show in Google Calendar (say Work or Classes). Calendars shared with them or subscribed to
// hold other people's plans, so they're left out.
export function ownCalendarIds(calendars: GoogleCalendarListEntry[]): string[] {
  return calendars
    .filter((calendar) => !calendar.deleted && (calendar.primary || (calendar.accessRole === "owner" && calendar.selected)))
    .map((calendar) => calendar.id);
}

// Reads every page. Recurring events are expanded into single instances.
// With a syncToken, a GoogleApiError with isSyncTokenExpired means a full sync is needed.
export async function listGoogleEvents(
  accessToken: string,
  input: ListGoogleEventsInput,
): Promise<ListGoogleEventsResult> {
  const calendarId = encodeURIComponent(input.calendarId ?? PRIMARY_CALENDAR);
  const baseParams =
    "syncToken" in input
      ? { syncToken: input.syncToken }
      : {
          timeMin: input.timeMin.toISOString(),
          timeMax: input.timeMax.toISOString(),
          orderBy: "startTime",
        };

  const events: GoogleEvent[] = [];
  let pageToken = input.pageToken;
  let nextSyncToken: string | null = null;
  do {
    const page = await googleRequest<GoogleEventList>(
      calendarUrl(`/calendars/${calendarId}/events`, {
        ...baseParams,
        singleEvents: "true",
        maxResults: String(input.maxResults ?? 250),
        pageToken,
      }),
      { headers: authHeaders(accessToken) },
    );
    events.push(...page.items);
    pageToken = page.nextPageToken;
    nextSyncToken = page.nextSyncToken ?? null;
  } while (pageToken);

  return { events, nextSyncToken };
}

export function getGoogleEvent(
  accessToken: string,
  eventId: string,
  calendarId = PRIMARY_CALENDAR,
): Promise<GoogleEvent> {
  return googleRequest<GoogleEvent>(
    calendarUrl(`/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`),
    { headers: authHeaders(accessToken) },
  );
}

// Busy periods only, without event details.
export async function listGoogleBusyPeriods(
  accessToken: string,
  timeMin: Date,
  timeMax: Date,
  calendarIds: string[] = [PRIMARY_CALENDAR],
): Promise<Record<string, GoogleTimePeriod[]>> {
  const response = await postJson<GoogleFreeBusyResponse>(accessToken, calendarUrl("/freeBusy"), {
    timeMin: timeMin.toISOString(),
    timeMax: timeMax.toISOString(),
    items: calendarIds.map((id) => ({ id })),
  });
  return Object.fromEntries(
    Object.entries(response.calendars).map(([id, calendar]) => [id, calendar.busy]),
  );
}

// Asks Google to POST to webhookUrl whenever the calendar's events change.
export function watchGoogleEvents(
  accessToken: string,
  input: WatchGoogleEventsInput,
): Promise<GoogleChannel> {
  const calendarId = encodeURIComponent(input.calendarId ?? PRIMARY_CALENDAR);
  return postJson<GoogleChannel>(accessToken, calendarUrl(`/calendars/${calendarId}/events/watch`), {
    id: input.channelId,
    type: "web_hook",
    address: input.webhookUrl,
    token: input.channelToken,
    params: input.ttlSeconds ? { ttl: String(input.ttlSeconds) } : undefined,
  });
}

export async function stopGoogleChannel(
  accessToken: string,
  channel: Pick<GoogleChannel, "id" | "resourceId">,
): Promise<void> {
  await postJson<void>(accessToken, calendarUrl("/channels/stop"), {
    id: channel.id,
    resourceId: channel.resourceId,
  });
}
