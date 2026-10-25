import { listSavedActivities, replaceSavedActivities } from "@/activities-service/activities-queries";
import { apiRoute, parseOrReject, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { replaceSavedActivitiesRequestSchema } from "@/validators/activities";

export default apiRoute({
  // GET /api/v1/users/{userId}/saved-activities — the activities the user picked as their own.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    res.status(200).json({ activities: await listSavedActivities(user.id) });
  },

  // PUT /api/v1/users/{userId}/saved-activities — replaces the picked activities.
  async PUT(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, replaceSavedActivitiesRequestSchema, req.body);
    if (!body) return;

    if (!(await replaceSavedActivities(user.id, body.activityIds))) {
      return sendError(res, "VALIDATION_FAILED", "activityIds: each must be a standard activity or one of your own");
    }
    res.status(200).json({ activities: await listSavedActivities(user.id) });
  },
});
