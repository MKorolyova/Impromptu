import { getStatusForUser, softDeleteStatus } from "@/statuses-service/statuses-queries";
import { apiRoute, sendError } from "@/utils/api-response";
import { readIdParam, requireUser } from "@/utils/route-params";

export default apiRoute({
  // GET /api/v1/users/{userId}/statuses/{statusId}
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const statusId = readIdParam(req, res, "statusId");
    if (!statusId) return;

    const status = await getStatusForUser(user.id, statusId);
    if (!status) return sendError(res, "NOT_FOUND", "Status not found");
    res.status(200).json({ status });
  },

  // DELETE /api/v1/users/{userId}/statuses/{statusId} — soft delete; the note goes with it.
  async DELETE(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const statusId = readIdParam(req, res, "statusId");
    if (!statusId) return;

    if (!(await softDeleteStatus(user.id, statusId))) return sendError(res, "NOT_FOUND", "Status not found");
    res.status(204).end();
  },
});
