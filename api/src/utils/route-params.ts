import type { NextApiRequest, NextApiResponse } from "next";
import { z } from "zod";
import { getUserById, type PublicUser } from "@/users-service/users-queries";
import { sendError } from "@/utils/api-response";

// Reads a UUID path segment like [userId]; sends NOT_FOUND for anything that isn't one.
export function readIdParam(req: NextApiRequest, res: NextApiResponse, name: string): string | null {
  const parsed = z.uuid().safeParse(req.query[name]);
  if (parsed.success) return parsed.data;
  sendError(res, "NOT_FOUND", `${name} must be a UUID`);
  return null;
}

// Loads the active user from [userId]; sends NOT_FOUND when missing or soft-deleted.
export async function requireUser(req: NextApiRequest, res: NextApiResponse): Promise<PublicUser | null> {
  const userId = readIdParam(req, res, "userId");
  if (!userId) return null;
  const user = await getUserById(userId);
  if (!user) sendError(res, "NOT_FOUND", "User not found");
  return user;
}
