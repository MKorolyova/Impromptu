import { checkGoogleCalendar } from "@/google-calendar-service/calendar-statuses";
import { GoogleApiError } from "@/google-calendar-service/google-request";
import { apiRoute, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";

export default apiRoute({
  // POST /api/v1/users/{userId}/google-calendar/check — re-reads today's events now and creates
  // statuses for events that have started, instead of waiting for the next minute's run.
  async POST(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    try {
      const result = await checkGoogleCalendar({ userId: user.id, timeZone: user.timezone }, { refresh: true });
      if (!result) return sendError(res, "NOT_FOUND", "Google Calendar is not connected");
      res.status(200).json({ check: result });
    } catch (error) {
      if (error instanceof GoogleApiError && error.isInvalidGrant) {
        return sendError(res, "FORBIDDEN", "Google access was revoked; connect Google Calendar again");
      }
      throw error;
    }
  },
});
