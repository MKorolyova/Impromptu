import { getFriend, removeFriend, updateFriendAccess } from "@/friends-service/friends-queries";
import { apiRoute, parseOrReject, sendError } from "@/utils/api-response";
import { readIdParam, requireUser } from "@/utils/route-params";
import { updateFriendRequestSchema } from "@/validators/friendships";

export default apiRoute({
  // PATCH /api/v1/users/{userId}/friends/{friendId} — changes what the friend can see.
  async PATCH(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const friendId = readIdParam(req, res, "friendId");
    if (!friendId) return;
    const body = parseOrReject(res, updateFriendRequestSchema, req.body);
    if (!body) return;

    if (!(await updateFriendAccess(user.id, friendId, body))) return sendError(res, "NOT_FOUND", "Friend not found");
    res.status(200).json({ friend: await getFriend(user.id, friendId) });
  },

  // DELETE /api/v1/users/{userId}/friends/{friendId} — removes the friend; they no longer see anything shared.
  async DELETE(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const friendId = readIdParam(req, res, "friendId");
    if (!friendId) return;

    if (!(await removeFriend(user.id, friendId))) return sendError(res, "NOT_FOUND", "Friend not found");
    res.status(204).end();
  },
});
