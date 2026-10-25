import { createUser } from "@/users-service/users-queries";
import { apiRoute, isUniqueViolation, parseOrReject, sendError } from "@/utils/api-response";
import { hashPassword } from "@/utils/password";
import { createUserRequestSchema } from "@/validators/users";

export default apiRoute({
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
