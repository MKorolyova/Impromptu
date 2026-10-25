import { findUserByEmail } from "@/users-service/users-queries";
import { apiRoute, parseOrReject } from "@/utils/api-response";
import { searchUsersRequestSchema } from "@/validators/users";

export default apiRoute({
  // POST /api/v1/users/search — finds a user by exact email (any capitalization). POST so the email
  // stays out of the URL and server logs. An empty list means no match.
  async POST(req, res) {
    const body = parseOrReject(res, searchUsersRequestSchema, req.body);
    if (!body) return;
    const user = await findUserByEmail(body.email);
    res.status(200).json({ users: user ? [user] : [] });
  },
});
