import { and, asc, desc, eq, isNull, or } from "drizzle-orm";
import { db } from "@/db/index";
import { activities } from "@/db/schema";
import type { CreateCustomActivityRequest } from "@/validators/activities";

const activityColumns = {
  id: activities.id,
  ownerId: activities.ownerId,
  name: activities.name,
  iconId: activities.iconId,
  defaultDurationMinutes: activities.defaultDurationMinutes,
  isCustom: activities.isCustom,
  createdAt: activities.createdAt,
  updatedAt: activities.updatedAt,
};

export type PublicActivity = {
  id: string;
  ownerId: string | null;
  name: string;
  iconId: string | null;
  defaultDurationMinutes: number;
  isCustom: boolean;
  createdAt: Date;
  updatedAt: Date;
};

// Standard activities plus the user's own, not deleted.
const isVisibleTo = (userId: string) =>
  and(isNull(activities.deletedAt), or(isNull(activities.ownerId), eq(activities.ownerId, userId)));

const isStandard = and(isNull(activities.ownerId), isNull(activities.deletedAt));

export function listActivitiesForUser(userId: string): Promise<PublicActivity[]> {
  return db
    .select(activityColumns)
    .from(activities)
    .where(isVisibleTo(userId))
    .orderBy(desc(activities.isCustom), asc(activities.name));
}

export async function getActivityForUser(
  userId: string,
  activityId: string,
): Promise<PublicActivity | null> {
  const [activity] = await db
    .select(activityColumns)
    .from(activities)
    .where(and(eq(activities.id, activityId), isVisibleTo(userId)))
    .limit(1);
  return activity ?? null;
}

export async function createCustomActivity(
  userId: string,
  input: CreateCustomActivityRequest,
): Promise<PublicActivity> {
  const [activity] = await db
    .insert(activities)
    .values({ ...input, ownerId: userId, isCustom: true })
    .returning(activityColumns);
  return activity;
}

// Only the owner's custom activities can be deleted; returns false otherwise.
export async function softDeleteCustomActivity(userId: string, activityId: string): Promise<boolean> {
  const deleted = await db
    .update(activities)
    .set({ deletedAt: new Date() })
    .where(
      and(eq(activities.id, activityId), eq(activities.ownerId, userId), isNull(activities.deletedAt)),
    )
    .returning({ id: activities.id });
  return deleted.length > 0;
}

export async function getStandardActivityByName(name: string): Promise<PublicActivity | null> {
  const [activity] = await db
    .select(activityColumns)
    .from(activities)
    .where(and(isStandard, eq(activities.name, name)))
    .limit(1);
  return activity ?? null;
}
