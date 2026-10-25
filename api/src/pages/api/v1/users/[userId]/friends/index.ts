import { addFriend, getFriend, listFriends } from "@/friends-service/friends-queries";
import { findUserByEmail } from "@/users-service/users-queries";
import { apiRoute, parseOrReject, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { addFriendRequestSchema } from "@/validators/friendships";

export default apiRoute({
  // GET /api/v1/users/{userId}/friends — people the user added, with what each can see.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    res.status(200).json({ friends: await listFriends(user.id) });
  },

  // POST /api/v1/users/{userId}/friends — adds someone by email, or changes what they can see if
  // they're already a friend.
  async POST(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, addFriendRequestSchema, req.body);
    if (!body) return;
    const { email, ...access } = body;

    const other = await findUserByEmail(email);
    if (!other) return sendError(res, "NOT_FOUND", "No one on Impromptu uses that email");
    if (other.id === user.id) return sendError(res, "VALIDATION_FAILED", "You can't add yourself");

    await addFriend(user.id, other.id, access);
    res.status(200).json({ friend: await getFriend(user.id, other.id) });
  },
});
