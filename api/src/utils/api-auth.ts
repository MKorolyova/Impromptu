import { createHash, timingSafeEqual } from "node:crypto";
import type { NextApiRequest } from "next";
import { env } from "@/env";

const sha256 = (value: string) => createHash("sha256").update(value).digest();

// Shared key for server-to-server callers, sent as `Authorization: Bearer <API_KEY>`.
// Stands in until user sign-in exists. Only enforced when API_KEY is set, so every request passes without it.
export function hasValidApiKey(req: NextApiRequest): boolean {
  const apiKey = env.API_KEY;
  if (!apiKey) return true;
  const header = req.headers.authorization ?? "";
  const [scheme, token] = header.split(" ");
  if (scheme !== "Bearer" || !token) return false;
  // Hashing first gives equal-length buffers, so the comparison is constant-time.
  return timingSafeEqual(sha256(token), sha256(apiKey));
}
