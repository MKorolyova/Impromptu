import {
  createCustomActivity,
  listActivitiesForUser,
} from "@/activities-service/activities-queries";
import { apiRoute, isUniqueViolation, parseOrReject, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { createCustomActivityRequestSchema } from "@/validators/activities";

export default apiRoute({
  // GET /api/v1/users/{userId}/activities — the user's custom activities first, then the standard ones.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    res.status(200).json({ activities: await listActivitiesForUser(user.id) });
  },

  // POST /api/v1/users/{userId}/activities — adds a custom activity.
  async POST(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, createCustomActivityRequestSchema, req.body);
    if (!body) return;

    try {
      res.status(201).json({ activity: await createCustomActivity(user.id, body) });
    } catch (error) {
      if (isUniqueViolation(error)) return sendError(res, "CONFLICT", "You already have an activity with this name");
      throw error;
    }
  },
});
