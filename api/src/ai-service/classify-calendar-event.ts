import { GeminiError, generateGeminiJson, isGeminiConfigured } from "@/ai-service/gemini-client";
import { ACTIVITIES } from "@/constants/activities";
import type { CalendarEvent } from "@/types/calendar-event";
import { localWeekdayAndTime } from "@/utils/time-zone";

const ACTIVITY_NAMES = ACTIVITIES.map((activity) => activity.name);
// Named by the prompt and the fallback rule, so they must stay in constants/activities.ts (a test checks).
const MEETING = "Meeting";
const FOCUS = "Deep focus";
const ANYTHING_ELSE = "Working";
// Matches Gemini's answer to a name even if capitals or spacing differ.
const normalize = (name: string) => name.trim().toLowerCase().replace(/\s+/g, " ");
const ACTIVITY_NAMES_BY_KEY = new Map(ACTIVITY_NAMES.map((name) => [normalize(name), name]));

export type CalendarEventClassification = {
  activityName: string;
  classifiedBy: "gemini" | "rule";
};

const SYSTEM_PROMPT = `You classify a calendar event into the one activity that best describes what the person is doing during it.
You must answer with exactly one activity name from the allowed list, spelled exactly as listed.
Use the title first, then the location, time of day, length, and whether other people are invited.
If the event has other attendees or a video call and nothing more specific fits, choose "${MEETING}".
If nothing fits well, choose "${ANYTHING_ELSE}".`;

// Used when Gemini isn't configured or fails, so a status is still created.
function classifyByRule(event: CalendarEvent): string {
  if (event.eventType === "focusTime") return FOCUS;
  if (event.hasOtherAttendees || event.videoCallUrl) return MEETING;
  return ANYTHING_ELSE;
}

// Picks one of the standard activities (constants/activities.ts) for an event.
// Only the title, location and simple facts are sent; never the description, attendees or other users' data.
// With `waitIfRateLimited`, returns null when Gemini is over its rate limit, so the caller can try
// again later instead of settling for the fallback rule.
export async function classifyCalendarEvent(
  event: CalendarEvent,
  timeZone: string,
  { waitIfRateLimited = false }: { waitIfRateLimited?: boolean } = {},
): Promise<CalendarEventClassification | null> {
  if (!isGeminiConfigured()) return { activityName: classifyByRule(event), classifiedBy: "rule" };

  const start = new Date(event.startAt);
  const facts = {
    title: event.title ?? "(no title)",
    location: event.location,
    startsAtLocalTime: localWeekdayAndTime(timeZone, start),
    durationMinutes: Math.round((new Date(event.endAt).getTime() - start.getTime()) / 60_000),
    googleEventType: event.eventType,
    hasOtherAttendees: event.hasOtherAttendees,
    hasVideoCall: event.videoCallUrl !== null,
  };

  try {
    const { activity } = await generateGeminiJson<{ activity?: unknown }>({
      system: SYSTEM_PROMPT,
      prompt: `Event:\n${JSON.stringify(facts, null, 2)}\n\nAllowed activities:\n${ACTIVITY_NAMES.join("\n")}`,
      // Gemini rejects an enum this long (over ~100 values), so the list is in the prompt and checked here.
      schema: {
        type: "OBJECT",
        properties: { activity: { type: "STRING", description: "One name from the allowed list, exactly as written" } },
        required: ["activity"],
      },
    });
    const activityName = typeof activity === "string" ? ACTIVITY_NAMES_BY_KEY.get(normalize(activity)) : undefined;
    if (activityName) return { activityName, classifiedBy: "gemini" };
    console.warn("Gemini picked an activity that isn't in the list; using the fallback rule");
  } catch (error) {
    if (waitIfRateLimited && error instanceof GeminiError && error.status === 429) return null;
    // Never log the event itself: titles are private.
    const reason = (error as Error).message.split("\n")[0];
    console.warn(`Gemini classification failed; using the fallback rule: ${reason}`);
  }
  return { activityName: classifyByRule(event), classifiedBy: "rule" };
}
