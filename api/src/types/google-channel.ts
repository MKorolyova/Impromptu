// Google Calendar v3 push notification channel shapes.
export type GoogleChannel = {
  kind: "api#channel";
  id: string;
  resourceId: string;
  resourceUri: string;
  token?: string;
  // Milliseconds since the epoch, as a string.
  expiration?: string;
};

export type WatchGoogleEventsInput = {
  calendarId?: string;
  channelId: string;
  webhookUrl: string;
  // Echoed back in the X-Goog-Channel-Token header, to verify notifications.
  channelToken: string;
  ttlSeconds?: number;
};
