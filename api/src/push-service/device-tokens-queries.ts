import { and, eq, inArray } from "drizzle-orm";
import { db } from "@/db/index";
import { deviceTokens } from "@/db/schema";
import type { PushEnvironmentValue } from "@/push-service/apns-protocol";

export type DeviceToken = { token: string; userId: string; environment: PushEnvironmentValue };

// Registers the device for this user. A token someone else registered moves to this user, since a
// device has one signed-in user at a time.
export async function saveDeviceToken(userId: string, token: string, environment: PushEnvironmentValue): Promise<void> {
  await db
    .insert(deviceTokens)
    .values({ token, userId, environment })
    .onConflictDoUpdate({ target: deviceTokens.token, set: { userId, environment, updatedAt: new Date() } });
}

// Only the user's own token can be removed. Returns false when it wasn't registered to them.
export async function deleteDeviceToken(userId: string, token: string): Promise<boolean> {
  const deleted = await db
    .delete(deviceTokens)
    .where(and(eq(deviceTokens.token, token), eq(deviceTokens.userId, userId)))
    .returning({ token: deviceTokens.token });
  return deleted.length > 0;
}

export function listDeviceTokens(userIds: string[]): Promise<DeviceToken[]> {
  if (userIds.length === 0) return Promise.resolve([]);
  return db
    .select({ token: deviceTokens.token, userId: deviceTokens.userId, environment: deviceTokens.environment })
    .from(deviceTokens)
    .where(inArray(deviceTokens.userId, userIds));
}

export async function deleteDeviceTokens(tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;
  await db.delete(deviceTokens).where(inArray(deviceTokens.token, tokens));
}

export async function updateDeviceTokenEnvironment(token: string, environment: PushEnvironmentValue): Promise<void> {
  await db.update(deviceTokens).set({ environment }).where(eq(deviceTokens.token, token));
}
