import { and, asc, desc, eq, inArray, isNull, or, sql } from "drizzle-orm";
import { db, withTransaction } from "@/db/index";
import { activities, userActivities } from "@/db/schema";
import type { ActivityDefinition } from "@/types/activity";
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

// Standard activities live in constants/activities.ts. Their database rows, which statuses and saved
// activities point at, are created the first time they're needed, so nothing depends on db:seed having run.
// Returns the rows' ids in the same order as `definitions`.
export async function ensureStandardActivities(definitions: readonly ActivityDefinition[]): Promise<string[]> {
  if (definitions.length === 0) return [];
  await db
    .insert(activities)
    .values(definitions.map(({ name, defaultDurationMinutes }) => ({ name, defaultDurationMinutes })))
    .onConflictDoNothing({ target: activities.name, where: sql`${activities.ownerId} IS NULL` });
  const rows = await db
    .select({ id: activities.id, name: activities.name })
    .from(activities)
    .where(and(isStandard, inArray(activities.name, definitions.map((definition) => definition.name))));
  const idByName = new Map(rows.map((row) => [row.name, row.id]));
  return definitions.flatMap((definition) => idByName.get(definition.name) ?? []);
}

// The activities the user picked as their own, in the same order as listActivitiesForUser.
// Deleted custom activities drop out.
export function listSavedActivities(userId: string): Promise<PublicActivity[]> {
  return db
    .select(activityColumns)
    .from(userActivities)
    .innerJoin(activities, eq(userActivities.activityId, activities.id))
    .where(and(eq(userActivities.userId, userId), isVisibleTo(userId)))
    .orderBy(desc(activities.isCustom), asc(activities.name));
}

// Replaces the user's picked activities. Returns false, saving nothing, if any id isn't a standard
// activity or one of the user's own.
export function replaceSavedActivities(userId: string, activityIds: string[]): Promise<boolean> {
  return withTransaction(async (tx) => {
    const visible = await tx
      .select({ id: activities.id })
      .from(activities)
      .where(and(inArray(activities.id, activityIds), isVisibleTo(userId)));
    if (visible.length !== activityIds.length) return false;

    await tx.delete(userActivities).where(eq(userActivities.userId, userId));
    await tx.insert(userActivities).values(activityIds.map((activityId) => ({ userId, activityId })));
    return true;
  });
}
