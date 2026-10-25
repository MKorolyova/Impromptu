import { randomBytes } from "node:crypto";
import { buildGoogleAuthUrl, revokeGoogleToken } from "@/google-calendar-service/auth";
import { forgetGoogleCalendarUser } from "@/google-calendar-service/calendar-statuses";
import {
  createOAuthState,
  deleteGoogleCalendarLink,
  getGoogleRefreshToken,
} from "@/google-calendar-service/google-calendar-queries";
import { apiRoute, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";

const STATE_TTL_MS = 10 * 60 * 1000;

export default apiRoute({
  // GET /api/v1/users/{userId}/google-calendar — whether Google Calendar is connected.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    res.status(200).json({ googleCalendar: { connected: (await getGoogleRefreshToken(user.id)) !== null } });
  },

  // POST /api/v1/users/{userId}/google-calendar — starts connecting. Open authUrl in
  // ASWebAuthenticationSession; Google returns to the callback, which redirects to APP_REDIRECT_URL.
  async POST(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const state = randomBytes(32).toString("hex");
    await createOAuthState(user.id, state, new Date(Date.now() + STATE_TTL_MS));
    res.status(200).json({ authUrl: buildGoogleAuthUrl(state) });
  },

  // DELETE /api/v1/users/{userId}/google-calendar — disconnects and revokes access.
  // Calendar statuses already created stay.
  async DELETE(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const refreshToken = await getGoogleRefreshToken(user.id);
    if (!refreshToken) return sendError(res, "NOT_FOUND", "Google Calendar is not connected");

    await revokeGoogleToken(refreshToken).catch(() => undefined);
    await deleteGoogleCalendarLink(user.id);
    forgetGoogleCalendarUser(user.id);
    res.status(204).end();
  },
});
