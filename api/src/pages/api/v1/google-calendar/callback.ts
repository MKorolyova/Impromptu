import type { NextApiResponse } from "next";
import { env } from "@/env";
import { exchangeGoogleAuthCode } from "@/google-calendar-service/auth";
import { checkGoogleCalendar, forgetGoogleCalendarUser } from "@/google-calendar-service/calendar-statuses";
import { consumeOAuthState, saveGoogleCalendarLink } from "@/google-calendar-service/google-calendar-queries";
import { getUserById } from "@/users-service/users-queries";
import { apiRoute } from "@/utils/api-response";

type CallbackResult = "connected" | "denied" | "expired" | "failed";

// Back to the app; ASWebAuthenticationSession closes when it sees APP_REDIRECT_URL.
function backToApp(res: NextApiResponse, result: CallbackResult) {
  const url = new URL(env.APP_REDIRECT_URL);
  url.searchParams.set("result", result);
  res.redirect(302, url.toString());
}

export default apiRoute(
  {
    // GET /api/v1/google-calendar/callback — Google redirects the browser here (GOOGLE_REDIRECT_URI).
    // Public: the one-time state ties it to the user who started connecting.
    async GET(req, res) {
      const { state, code, error } = req.query;
      if (typeof state !== "string") return backToApp(res, "expired");
      const userId = await consumeOAuthState(state);
      if (!userId) return backToApp(res, "expired");
      if (typeof error === "string") return backToApp(res, "denied");
      if (typeof code !== "string") return backToApp(res, "failed");

      try {
        const tokens = await exchangeGoogleAuthCode(code);
        if (!tokens.refreshToken) return backToApp(res, "failed");
        await saveGoogleCalendarLink(userId, tokens.refreshToken);
        forgetGoogleCalendarUser(userId);
      } catch (err) {
        console.error(`Google Calendar connect failed: ${(err as Error).message}`);
        return backToApp(res, "failed");
      }
      backToApp(res, "connected");

      // Pick up an event that's already in progress without waiting for the next run.
      const user = await getUserById(userId);
      if (user) {
        checkGoogleCalendar({ userId, timeZone: user.timezone }).catch((err) =>
          console.error(`First Google Calendar check failed: ${(err as Error).message}`),
        );
      }
    },
  },
  { public: true },
);
