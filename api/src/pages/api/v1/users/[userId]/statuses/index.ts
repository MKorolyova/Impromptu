import { getActivityForUser } from "@/activities-service/activities-queries";
import { announceNearbyMatchesLater } from "@/locations-service/nearby-alerts";
import { createStatus, listStatusesForUser } from "@/statuses-service/statuses-queries";
import { apiRoute, parseOrReject, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { createStatusRequestSchema } from "@/validators/statuses";

export default apiRoute({
  // GET /api/v1/users/{userId}/statuses[?active=true]
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const active = req.query.active === "true";
    res.status(200).json({ statuses: await listStatusesForUser(user.id, { active }) });
  },

  // POST /api/v1/users/{userId}/statuses — sets an activity with an optional note. People within 3 miles
  // already doing the same activity then get a push about the user.
  async POST(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, createStatusRequestSchema, req.body);
    if (!body) return;

    const activity = await getActivityForUser(user.id, body.activityId);
    if (!activity) return sendError(res, "NOT_FOUND", "Activity not found");

    const startedAt = new Date();
    const expiresAt =
      body.expiresAt ?? new Date(startedAt.getTime() + activity.defaultDurationMinutes * 60_000);
    const status = await createStatus({
      userId: user.id,
      activityId: activity.id,
      note: body.note || null,
      source: "MANUAL",
      startedAt,
      expiresAt,
    });
    res.status(201).json({ status });
    announceNearbyMatchesLater(user.id);
  },
});
