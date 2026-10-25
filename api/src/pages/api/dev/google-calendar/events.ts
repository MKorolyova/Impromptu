import type { NextApiRequest, NextApiResponse } from "next";
import { z } from "zod";
import { refreshGoogleAccessToken } from "../../../../google-calendar-service/auth.ts";
import { listGoogleEvents } from "../../../../google-calendar-service/google-calendar.ts";
import {
  getGoogleCalendarLink,
  getGoogleRefreshToken,
  updateGoogleSyncToken,
} from "../../../../google-calendar-service/google-calendar-queries.ts";
import { GoogleApiError } from "../../../../google-calendar-service/google-request.ts";
import { blockOutsideDevelopment, rejectMethod, sendError, withApiErrors } from "../../../../utils/test/api-response.ts";

const DAYS_AHEAD = 7;

// Reads the next week of events from the user's primary calendar.
export default withApiErrors(async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (blockOutsideDevelopment(res)) return;
  if (req.method !== "GET") return rejectMethod(res, ["GET"]);

  const userId = z.uuid().safeParse(req.query.userId);
  if (!userId.success) return sendError(res, "VALIDATION_FAILED", "userId must be a UUID");

  const refreshToken = await getGoogleRefreshToken(userId.data);
  if (!refreshToken) return sendError(res, "NOT_FOUND", "Google Calendar is not connected for this user");

  try {
    const { accessToken } = await refreshGoogleAccessToken(refreshToken);
    const timeMin = new Date();
    const timeMax = new Date(timeMin.getTime() + DAYS_AHEAD * 24 * 60 * 60 * 1000);
    const { events, nextSyncToken } = await listGoogleEvents(accessToken, { timeMin, timeMax });
    if (nextSyncToken) await updateGoogleSyncToken(userId.data, nextSyncToken);

    res.status(200).json({
      link: await getGoogleCalendarLink(userId.data),
      events: events.map((event) => ({
        id: event.id,
        summary: event.summary ?? null,
        status: event.status,
        start: event.start.dateTime ?? event.start.date ?? null,
        end: event.end.dateTime ?? event.end.date ?? null,
        allDay: !event.start.dateTime,
        location: event.location ?? null,
      })),
    });
  } catch (error) {
    if (error instanceof GoogleApiError && error.isInvalidGrant) {
      return sendError(res, "UNAUTHORIZED", "Google access was revoked. Connect again.");
    }
    if (error instanceof GoogleApiError) return sendError(res, "INTERNAL", `Google: ${error.message}`);
    throw error;
  }
});
