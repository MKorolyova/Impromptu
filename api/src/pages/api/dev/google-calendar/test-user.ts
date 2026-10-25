import type { NextApiRequest, NextApiResponse } from "next";
import { db } from "../../../../db/index.ts";
import { users } from "../../../../db/schema.ts";
import { blockOutsideDevelopment, rejectMethod, sendError, withApiErrors } from "../../../../utils/test/api-response.ts";
import { createUserSchema } from "../../../../validators/users.ts";

// Creates a user to attach a Google calendar to. It cannot log in.
export default withApiErrors(async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (blockOutsideDevelopment(res)) return;
  if (req.method !== "POST") return rejectMethod(res, ["POST"]);

  const parsed = createUserSchema.safeParse({ ...req.body, passwordHash: "dev-test-user-no-login" });
  if (!parsed.success) {
    return sendError(res, "VALIDATION_FAILED", parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; "));
  }

  try {
    const [user] = await db
      .insert(users)
      .values(parsed.data)
      .returning({ id: users.id, email: users.email, firstName: users.firstName });
    res.status(201).json({ user });
  } catch (error) {
    if ((error as { code?: string }).code === "23505") {
      return sendError(res, "CONFLICT", "A user with this email already exists");
    }
    throw error;
  }
});
