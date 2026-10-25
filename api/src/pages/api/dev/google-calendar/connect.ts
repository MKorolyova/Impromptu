import { randomBytes } from "node:crypto";
import type { NextApiRequest, NextApiResponse } from "next";
import { z } from "zod";
import { buildGoogleAuthUrl } from "../../../../google-calendar-service/auth.ts";
import { blockOutsideDevelopment, rejectMethod, sendError } from "../../../../utils/test/api-response.ts";

export const OAUTH_STATE_COOKIE = "google_oauth_state";

// Sends the browser to Google's consent screen. The state cookie ties the callback to this user.
export default function handler(req: NextApiRequest, res: NextApiResponse) {
  if (blockOutsideDevelopment(res)) return;
  if (req.method !== "GET") return rejectMethod(res, ["GET"]);

  const userId = z.uuid().safeParse(req.query.userId);
  if (!userId.success) return sendError(res, "VALIDATION_FAILED", "userId must be a UUID");

  const state = randomBytes(32).toString("hex");
  let authUrl: string;
  try {
    authUrl = buildGoogleAuthUrl(state);
  } catch (error) {
    // This is a browser navigation, so report problems (e.g. missing GOOGLE_* settings) on the test page.
    const params = new URLSearchParams({ userId: userId.data, error: (error as Error).message });
    res.redirect(302, `/google-calendar-test?${params}`);
    return;
  }
  res.setHeader(
    "Set-Cookie",
    `${OAUTH_STATE_COOKIE}=${state}.${userId.data}; Path=/api/dev/google-calendar; HttpOnly; SameSite=Lax; Max-Age=600`,
  );
  res.redirect(302, authUrl);
}
