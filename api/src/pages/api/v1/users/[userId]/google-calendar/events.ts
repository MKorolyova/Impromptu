import { becomesStatus, readTodayGoogleCalendarEvents } from "@/google-calendar-service/calendar-statuses";
import { GoogleApiError } from "@/google-calendar-service/google-request";
import { apiRoute, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";

export default apiRoute({
  // GET /api/v1/users/{userId}/google-calendar/events — the rest of today (in the user's time zone),
  // read live from Google. `becomesStatus` says whether the event will turn into a status when it starts.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    try {
      const events = await readTodayGoogleCalendarEvents({ userId: user.id, timeZone: user.timezone });
      if (!events) return sendError(res, "NOT_FOUND", "Google Calendar is not connected");
      res.status(200).json({ events: events.map((event) => ({ ...event, becomesStatus: becomesStatus(event) })) });
    } catch (error) {
      if (error instanceof GoogleApiError && error.isInvalidGrant) {
        return sendError(res, "FORBIDDEN", "Google access was revoked; connect Google Calendar again");
      }
      throw error;
    }
  },
});
