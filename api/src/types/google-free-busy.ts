// Google Calendar v3 free/busy shapes.
export type GoogleTimePeriod = {
  start: string;
  end: string;
};

export type GoogleFreeBusyResponse = {
  kind: "calendar#freeBusy";
  timeMin: string;
  timeMax: string;
  calendars: Record<
    string,
    {
      busy: GoogleTimePeriod[];
      errors?: { domain: string; reason: string }[];
    }
  >;
};
