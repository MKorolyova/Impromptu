import { createUser, listUsers, type UsersCursor } from "@/users-service/users-queries";
import { apiRoute, isUniqueViolation, parseOrReject, sendError } from "@/utils/api-response";
import { hashPassword } from "@/utils/password";
import { createUserRequestSchema, listUsersQuerySchema } from "@/validators/users";

// The cursor is opaque to callers: base64url of "<createdAt ISO>|<id>".
const encodeCursor = (cursor: UsersCursor) =>
  Buffer.from(`${cursor.createdAt.toISOString()}|${cursor.id}`).toString("base64url");

function decodeCursor(value: string): UsersCursor | null {
  const [createdAt, id] = Buffer.from(value, "base64url").toString().split("|");
  const date = new Date(createdAt);
  return id && !Number.isNaN(date.getTime()) ? { createdAt: date, id } : null;
}

export default apiRoute({
  // GET /api/v1/users?limit=&cursor= — all users, oldest first, a page at a time.
  async GET(req, res) {
    const query = parseOrReject(res, listUsersQuerySchema, req.query);
    if (!query) return;
    const after = query.cursor ? decodeCursor(query.cursor) : undefined;
    if (after === null) return sendError(res, "VALIDATION_FAILED", "cursor is invalid");

    // One extra row tells whether there's another page.
    const rows = await listUsers({ limit: query.limit + 1, after });
    const users = rows.slice(0, query.limit);
    const last = users.at(-1);
    res.status(200).json({ users, nextCursor: rows.length > query.limit && last ? encodeCursor(last) : null });
  },

  // POST /api/v1/users
  async POST(req, res) {
    const body = parseOrReject(res, createUserRequestSchema, req.body);
    if (!body) return;
    const { password, ...profile } = body;

    try {
      const user = await createUser({ ...profile, passwordHash: await hashPassword(password) });
      res.status(201).json({ user });
    } catch (error) {
      if (isUniqueViolation(error)) return sendError(res, "CONFLICT", "An account with this email already exists");
      throw error;
    }
  },
});
