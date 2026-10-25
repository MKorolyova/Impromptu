import { and, desc, eq, gt, inArray, isNotNull, isNull, lte } from "drizzle-orm";
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

// Each user's newest active status, keyed by user ID. Users without one are absent.
export async function getCurrentStatuses(userIds: string[]): Promise<Map<string, PublicStatus>> {
  const current = new Map<string, PublicStatus>();
  if (userIds.length === 0) return current;
  const now = new Date();
  const rows = await selectStatuses()
    .where(
      and(
        inArray(statuses.userId, userIds),
        isNull(statuses.deletedAt),
        lte(statuses.startedAt, now),
        gt(statuses.expiresAt, now),
      ),
    )
    .orderBy(desc(statuses.startedAt));
  for (const status of rows) {
    if (!current.has(status.userId)) current.set(status.userId, status);
  }
  return current;
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

export type CalendarStatusInput = {
  userId: string;
  activityId: string;
  googleEventId: string;
  startedAt: Date;
  expiresAt: Date;
};

// Whether this event start already produced a status, including one the user deleted since,
// so a deleted calendar status isn't recreated.
export async function hasCalendarStatus(userId: string, googleEventId: string, startedAt: Date): Promise<boolean> {
  const [row] = await db
    .select({ id: statuses.id })
    .from(statuses)
    .where(
      and(
        eq(statuses.userId, userId),
        eq(statuses.googleEventId, googleEventId),
        eq(statuses.startedAt, startedAt),
      ),
    )
    .limit(1);
  return Boolean(row);
}

// Returns null if a status for this event already exists (another server got there first).
export async function createCalendarStatus(input: CalendarStatusInput): Promise<PublicStatus | null> {
  const [row] = await db
    .insert(statuses)
    .values({ ...input, source: "CALENDAR", note: null })
    .onConflictDoNothing()
    .returning({ id: statuses.id });
  if (!row) return null;
  const [status] = await selectStatuses().where(eq(statuses.id, row.id));
  return status;
}

export type ActiveCalendarStatus = { id: string; googleEventId: string; startedAt: Date; expiresAt: Date };

// The user's CALENDAR statuses that haven't ended yet.
export async function listActiveCalendarStatuses(userId: string, now: Date): Promise<ActiveCalendarStatus[]> {
  const rows = await db
    .select({
      id: statuses.id,
      googleEventId: statuses.googleEventId,
      startedAt: statuses.startedAt,
      expiresAt: statuses.expiresAt,
    })
    .from(statuses)
    .where(
      and(
        isUsersStatus(userId),
        eq(statuses.source, "CALENDAR"),
        isNotNull(statuses.googleEventId),
        gt(statuses.expiresAt, now),
      ),
    );
  return rows.map((row) => ({ ...row, googleEventId: row.googleEventId! }));
}

export async function updateStatusExpiresAt(statusId: string, expiresAt: Date): Promise<void> {
  await db.update(statuses).set({ expiresAt }).where(eq(statuses.id, statusId));
}
