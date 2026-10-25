import {
  ensureStandardActivities,
  listSavedActivities,
  replaceSavedActivities,
} from "@/activities-service/activities-queries";
import { ACTIVITIES } from "@/constants/activities";
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

  // PUT /api/v1/users/{userId}/saved-activities — replaces the picked activities. Standard ones can be
  // sent by name, as listed by GET /api/v1/activities.
  async PUT(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, replaceSavedActivitiesRequestSchema, req.body);
    if (!body) return;

    const standard = body.standardActivityNames.map((name) => ACTIVITIES.find((activity) => activity.name === name));
    const unknown = body.standardActivityNames.filter((_, index) => !standard[index]);
    if (unknown.length > 0) {
      return sendError(res, "VALIDATION_FAILED", `standardActivityNames: not standard activities: ${unknown.join(", ")}`);
    }
    const standardIds = await ensureStandardActivities(standard.filter((activity) => activity !== undefined));
    const activityIds = [...new Set([...body.activityIds, ...standardIds])];

    if (!(await replaceSavedActivities(user.id, activityIds))) {
      return sendError(res, "VALIDATION_FAILED", "activityIds: each must be a standard activity or one of your own");
    }
    res.status(200).json({ activities: await listSavedActivities(user.id) });
  },
});
