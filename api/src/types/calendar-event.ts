// A Google Calendar event as this app uses it. Read live from Google; the raw event is never stored.
export type CalendarEvent = {
  id: string;
  title: string | null;
  location: string | null;
  // ISO 8601. All-day events start at 00:00 UTC of their date and end at 00:00 UTC the day after.
  startAt: string;
  endAt: string;
  allDay: boolean;
  status: "confirmed" | "tentative";
  // The user's own answer, or null when they're the only person on the event.
  responseStatus: "needsAction" | "declined" | "tentative" | "accepted" | null;
  hasOtherAttendees: boolean;
  videoCallUrl: string | null;
  // "default", "focusTime", "outOfOffice", "workingLocation", "birthday" or "fromGmail".
  eventType: string;
  // Marked "Free" in Google, so it doesn't make the user busy.
  free: boolean;
};
