// Google Calendar v3 calendar list shapes. Only fields this app may use are listed.
export type GoogleAccessRole = "freeBusyReader" | "reader" | "writer" | "owner";

export type GoogleCalendarListEntry = {
  kind: "calendar#calendarListEntry";
  etag: string;
  id: string;
  summary: string;
  summaryOverride?: string;
  description?: string;
  location?: string;
  timeZone?: string;
  colorId?: string;
  backgroundColor?: string;
  foregroundColor?: string;
  hidden?: boolean;
  selected?: boolean;
  primary?: boolean;
  deleted?: boolean;
  accessRole: GoogleAccessRole;
};

export type GoogleCalendarList = {
  kind: "calendar#calendarList";
  etag: string;
  nextPageToken?: string;
  nextSyncToken?: string;
  items: GoogleCalendarListEntry[];
};
