import { softDeleteUser } from "@/users-service/users-queries";
import { apiRoute, sendError } from "@/utils/api-response";
import { readIdParam, requireUser } from "@/utils/route-params";

export default apiRoute({
  // GET /api/v1/users/{userId}
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    res.status(200).json({ user });
  },

  // DELETE /api/v1/users/{userId} — soft delete; the email can be used again.
  async DELETE(req, res) {
    const userId = readIdParam(req, res, "userId");
    if (!userId) return;
    if (!(await softDeleteUser(userId))) return sendError(res, "NOT_FOUND", "User not found");
    res.status(204).end();
  },
});
