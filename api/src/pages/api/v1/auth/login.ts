import { getUserCredentialsByEmail } from "@/users-service/users-queries";
import { apiRoute, parseOrReject, sendError } from "@/utils/api-response";
import { hashPassword, verifyPassword } from "@/utils/password";
import { loginRequestSchema } from "@/validators/users";

// Checked when the email is unknown, so both failures take about as long.
let dummyHash: Promise<string> | undefined;

export default apiRoute({
  // POST /api/v1/auth/login — checks email and password and returns the user.
  async POST(req, res) {
    const body = parseOrReject(res, loginRequestSchema, req.body);
    if (!body) return;

    const credentials = await getUserCredentialsByEmail(body.email);
    const storedHash = credentials?.passwordHash ?? (await (dummyHash ??= hashPassword("not-a-real-password")));
    const valid = await verifyPassword(body.password, storedHash);

    if (!credentials || !valid) return sendError(res, "UNAUTHORIZED", "Invalid email or password");
    res.status(200).json({ user: credentials.user });
  },
});
