import { and, desc, eq, gt, isNull, lte } from "drizzle-orm";
import { db } from "@/db/index";
import { activities, statuses } from "@/db/schema";

export type StatusSourceValue = (typeof statuses.$inferInsert)["source"];

export type CreateStatusInput = {
  userId: string;
  activityId: string;
  note: string | null;
  source: StatusSourceValue;
  startedAt: Date;
  expiresAt: Date;
};

export type PublicStatus = {
  id: string;
  userId: string;
  note: string | null;
  source: StatusSourceValue;
  startedAt: Date;
  expiresAt: Date;
  createdAt: Date;
  updatedAt: Date;
  activity: { id: string; name: string; iconId: string | null; isCustom: boolean };
};

const statusColumns = {
  id: statuses.id,
  userId: statuses.userId,
  note: statuses.note,
  source: statuses.source,
  startedAt: statuses.startedAt,
  expiresAt: statuses.expiresAt,
  createdAt: statuses.createdAt,
  updatedAt: statuses.updatedAt,
  activity: {
    id: activities.id,
    name: activities.name,
    iconId: activities.iconId,
    isCustom: activities.isCustom,
  },
};

const isUsersStatus = (userId: string) => and(eq(statuses.userId, userId), isNull(statuses.deletedAt));

function selectStatuses() {
  return db.select(statusColumns).from(statuses).innerJoin(activities, eq(activities.id, statuses.activityId));
}

export async function createStatus(input: CreateStatusInput): Promise<PublicStatus> {
  const [{ id }] = await db.insert(statuses).values(input).returning({ id: statuses.id });
  const [status] = await selectStatuses().where(eq(statuses.id, id));
  return status;
}

// Newest first. `active` keeps only statuses that have started and not yet expired.
export function listStatusesForUser(
  userId: string,
  { active = false, limit = 50 }: { active?: boolean; limit?: number } = {},
): Promise<PublicStatus[]> {
  const now = new Date();
  return selectStatuses()
    .where(
      active
        ? and(isUsersStatus(userId), lte(statuses.startedAt, now), gt(statuses.expiresAt, now))
        : isUsersStatus(userId),
    )
    .orderBy(desc(statuses.startedAt))
    .limit(limit);
}

export async function getStatusForUser(userId: string, statusId: string): Promise<PublicStatus | null> {
  const [status] = await selectStatuses()
    .where(and(eq(statuses.id, statusId), isUsersStatus(userId)))
    .limit(1);
  return status ?? null;
}

export async function softDeleteStatus(userId: string, statusId: string): Promise<boolean> {
  const deleted = await db
    .update(statuses)
    .set({ deletedAt: new Date() })
    .where(and(eq(statuses.id, statusId), isUsersStatus(userId)))
    .returning({ id: statuses.id });
  return deleted.length > 0;
}
