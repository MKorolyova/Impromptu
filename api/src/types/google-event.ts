import type { GoogleAccessRole } from "@/types/google-calendar";

// Google Calendar v3 event shapes. Only fields this app may use are listed.
// All-day events use `date` (YYYY-MM-DD); timed events use `dateTime` (RFC 3339).
export type GoogleEventDateTime = {
  date?: string;
  dateTime?: string;
  timeZone?: string;
};

export type GoogleEventPerson = {
  id?: string;
  email?: string;
  displayName?: string;
  self?: boolean;
};

export type GoogleEventAttendee = GoogleEventPerson & {
  organizer?: boolean;
  resource?: boolean;
  optional?: boolean;
  responseStatus: "needsAction" | "declined" | "tentative" | "accepted";
  comment?: string;
  additionalGuests?: number;
};

export type GoogleEventStatus = "confirmed" | "tentative" | "cancelled";

export type GoogleEventType =
  | "default"
  | "birthday"
  | "focusTime"
  | "fromGmail"
  | "outOfOffice"
  | "workingLocation";

export type GoogleEvent = {
  kind: "calendar#event";
  etag: string;
  id: string;
  status: GoogleEventStatus;
  htmlLink: string;
  created: string;
  updated: string;
  summary?: string;
  description?: string;
  location?: string;
  colorId?: string;
  creator?: GoogleEventPerson;
  organizer?: GoogleEventPerson;
  start: GoogleEventDateTime;
  end: GoogleEventDateTime;
  endTimeUnspecified?: boolean;
  recurrence?: string[];
  recurringEventId?: string;
  originalStartTime?: GoogleEventDateTime;
  transparency?: "opaque" | "transparent";
  visibility?: "default" | "public" | "private" | "confidential";
  iCalUID: string;
  sequence: number;
  attendees?: GoogleEventAttendee[];
  hangoutLink?: string;
  eventType?: GoogleEventType;
};

export type GoogleEventList = {
  kind: "calendar#events";
  etag: string;
  summary: string;
  description?: string;
  updated: string;
  timeZone: string;
  accessRole: GoogleAccessRole;
  nextPageToken?: string;
  // Present only on the last page.
  nextSyncToken?: string;
  items: GoogleEvent[];
};

export type ListGoogleEventsInput =
  | {
      calendarId?: string;
      timeMin: Date;
      timeMax: Date;
      pageToken?: string;
      maxResults?: number;
    }
  | {
      // Incremental sync: Google rejects time ranges and ordering together with a sync token.
      calendarId?: string;
      syncToken: string;
      pageToken?: string;
      maxResults?: number;
    };

export type ListGoogleEventsResult = {
  events: GoogleEvent[];
  nextSyncToken: string | null;
};
