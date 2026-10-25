import type { NextApiRequest, NextApiResponse } from "next";
import { exchangeGoogleAuthCode } from "../../../../google-calendar-service/auth.ts";
import { saveGoogleCalendarLink } from "../../../../google-calendar-service/google-calendar-queries.ts";
import { GoogleApiError } from "../../../../google-calendar-service/google-request.ts";
import {
  DATABASE_UNREACHABLE_MESSAGE,
  blockOutsideDevelopment,
  isDatabaseUnreachable,
  rejectMethod,
} from "../../../../utils/test/api-response.ts";
import { OAUTH_STATE_COOKIE } from "./connect.ts";

const TEST_PAGE = "/google-calendar-test";

function backToTestPage(res: NextApiResponse, params: Record<string, string>) {
  res.setHeader("Set-Cookie", `${OAUTH_STATE_COOKIE}=; Path=/api/dev/google-calendar; HttpOnly; SameSite=Lax; Max-Age=0`);
  res.redirect(302, `${TEST_PAGE}?${new URLSearchParams(params)}`);
}

// Google redirects here after the consent screen (GOOGLE_REDIRECT_URI).
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (blockOutsideDevelopment(res)) return;
  if (req.method !== "GET") return rejectMethod(res, ["GET"]);

  const [expectedState, userId] = (req.cookies[OAUTH_STATE_COOKIE] ?? "").split(".");
  if (typeof req.query.error === "string") {
    return backToTestPage(res, { userId: userId ?? "", error: `Google: ${req.query.error}` });
  }
  if (!expectedState || !userId || req.query.state !== expectedState) {
    return backToTestPage(res, { error: "Sign-in expired or did not match. Try connecting again." });
  }
  if (typeof req.query.code !== "string") {
    return backToTestPage(res, { userId, error: "Google did not return a code" });
  }

  try {
    const tokens = await exchangeGoogleAuthCode(req.query.code);
    if (!tokens.refreshToken) {
      return backToTestPage(res, { userId, error: "Google did not return a refresh token" });
    }
    await saveGoogleCalendarLink(userId, tokens.refreshToken);
    backToTestPage(res, { userId, connected: "1" });
  } catch (error) {
    const message =
      error instanceof GoogleApiError
        ? `Google: ${error.message}`
        : isDatabaseUnreachable(error)
          ? DATABASE_UNREACHABLE_MESSAGE
          : "Could not save the connection";
    backToTestPage(res, { userId, error: message });
  }
}
