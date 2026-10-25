import type { NextApiRequest, NextApiResponse } from "next";
import { z } from "zod";
import { revokeGoogleToken } from "../../../../google-calendar-service/auth.ts";
import {
  deleteGoogleCalendarLink,
  getGoogleRefreshToken,
} from "../../../../google-calendar-service/google-calendar-queries.ts";
import { blockOutsideDevelopment, rejectMethod, sendError, withApiErrors } from "../../../../utils/test/api-response.ts";

export default withApiErrors(async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (blockOutsideDevelopment(res)) return;
  if (req.method !== "POST") return rejectMethod(res, ["POST"]);

  const userId = z.uuid().safeParse(req.body?.userId);
  if (!userId.success) return sendError(res, "VALIDATION_FAILED", "userId must be a UUID");

  const refreshToken = await getGoogleRefreshToken(userId.data);
  if (!refreshToken) return sendError(res, "NOT_FOUND", "Google Calendar is not connected for this user");

  // Remove our copy even if Google has already forgotten the token.
  await revokeGoogleToken(refreshToken).catch(() => undefined);
  await deleteGoogleCalendarLink(userId.data);
  res.status(204).end();
});
