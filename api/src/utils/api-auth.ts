import { createHash, timingSafeEqual } from "node:crypto";
import type { NextApiRequest } from "next";
import { env } from "@/env";

const sha256 = (value: string) => createHash("sha256").update(value).digest();

// Shared key for server-to-server callers, sent as `Authorization: Bearer <API_KEY>`.
// Stands in until user sign-in exists.
export function hasValidApiKey(req: NextApiRequest): boolean {
  const header = req.headers.authorization ?? "";
  const [scheme, token] = header.split(" ");
  if (scheme !== "Bearer" || !token) return false;
  // Hashing first gives equal-length buffers, so the comparison is constant-time.
  return timingSafeEqual(sha256(token), sha256(env.API_KEY));
}
