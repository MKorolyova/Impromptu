import {
  getActivityForUser,
  softDeleteCustomActivity,
} from "@/activities-service/activities-queries";
import { apiRoute, sendError } from "@/utils/api-response";
import { readIdParam, requireUser } from "@/utils/route-params";

export default apiRoute({
  // GET /api/v1/users/{userId}/activities/{activityId}
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const activityId = readIdParam(req, res, "activityId");
    if (!activityId) return;

    const activity = await getActivityForUser(user.id, activityId);
    if (!activity) return sendError(res, "NOT_FOUND", "Activity not found");
    res.status(200).json({ activity });
  },

  // DELETE /api/v1/users/{userId}/activities/{activityId} — soft delete; standard activities can't be deleted.
  async DELETE(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const activityId = readIdParam(req, res, "activityId");
    if (!activityId) return;

    const activity = await getActivityForUser(user.id, activityId);
    if (!activity) return sendError(res, "NOT_FOUND", "Activity not found");
    if (!activity.isCustom) return sendError(res, "FORBIDDEN", "Standard activities can't be deleted");

    await softDeleteCustomActivity(user.id, activityId);
    res.status(204).end();
  },
});
