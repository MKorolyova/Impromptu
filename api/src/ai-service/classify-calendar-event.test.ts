import assert from "node:assert/strict";
import { test } from "node:test";
import { ACTIVITIES } from "../constants/activities.ts";
import type { CalendarEvent } from "../types/calendar-event.ts";
import { classifyCalendarEvent } from "./classify-calendar-event.ts";

// Without a Gemini key the fallback rule decides, with no network calls.
delete process.env.GEMINI_API_KEY;

const event = (overrides: Partial<CalendarEvent> = {}): CalendarEvent => ({
  id: "event-1",
  title: "Weekly sync",
  location: null,
  startAt: "2026-10-26T15:00:00Z",
  endAt: "2026-10-26T15:30:00Z",
  allDay: false,
  status: "confirmed",
  responseStatus: "accepted",
  hasOtherAttendees: false,
  videoCallUrl: null,
  eventType: "default",
  free: false,
  ...overrides,
});

const classify = async (overrides: Partial<CalendarEvent>) =>
  (await classifyCalendarEvent(event(overrides), "America/Chicago"))?.activityName;

test("the fallback rule only picks activities that exist", async () => {
  const names = new Set(ACTIVITIES.map((activity) => activity.name));
  const picks = [
    await classify({ hasOtherAttendees: true }),
    await classify({ videoCallUrl: "https://meet.google.com/abc-defg-hij" }),
    await classify({ eventType: "focusTime" }),
    await classify({}),
  ];
  assert.deepEqual(picks, ["Meeting", "Meeting", "Deep focus", "Working"]);
  for (const pick of picks) assert.ok(names.has(pick!), `${pick} isn't in constants/activities.ts`);
});
