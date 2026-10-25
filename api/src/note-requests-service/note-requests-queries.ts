import { and, desc, eq, gt, inArray, or, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { db } from "@/db/index";
import { activities, noteRequests, users } from "@/db/schema";
import type { UserProfile } from "@/users-service/users-queries";
import type { ReplyToNoteRequest } from "@/validators/note-requests";

// How long a request can be answered; statuses are short-lived too.
export const NOTE_REQUEST_LIFETIME_MS = 3 * 60 * 60 * 1000;

type NoteRequestStatusValue = (typeof noteRequests.$inferSelect)["status"];

// A request as one side of it sees it: `otherUser` is the person on the other end.
export type NoteRequestView = {
  id: string;
  direction: "INCOMING" | "OUTGOING";
  otherUser: UserProfile;
  activity: { id: string; name: string; iconId: string | null; isCustom: boolean } | null;
  status: NoteRequestStatusValue;
  // Pending past expiresAt; can no longer be answered.
  isExpired: boolean;
  createdAt: Date;
  expiresAt: Date;
  reply: {
    text: string;
    placeLabel: string | null;
    location: { latitude: number; longitude: number } | null;
    respondedAt: Date;
  } | null;
};

const requester = alias(users, "requester");
const recipient = alias(users, "recipient");
const profileOf = (table: typeof requester | typeof recipient) => ({
  id: table.id,
  firstName: table.firstName,
  lastName: table.lastName,
  nickname: table.nickname,
});

function selectNoteRequests() {
  return db
    .select({
      id: noteRequests.id,
      status: noteRequests.status,
      replyText: noteRequests.replyText,
      replyPlaceLabel: noteRequests.replyPlaceLabel,
      // Stored lon/lat: x is longitude, y is latitude.
      replyLatitude: sql<number | null>`ST_Y(${noteRequests.replyGeom})`,
      replyLongitude: sql<number | null>`ST_X(${noteRequests.replyGeom})`,
      respondedAt: noteRequests.respondedAt,
      expiresAt: noteRequests.expiresAt,
      createdAt: noteRequests.createdAt,
      activity: { id: activities.id, name: activities.name, iconId: activities.iconId, isCustom: activities.isCustom },
      requester: profileOf(requester),
      recipient: profileOf(recipient),
    })
    .from(noteRequests)
    .innerJoin(requester, eq(requester.id, noteRequests.requesterId))
    .innerJoin(recipient, eq(recipient.id, noteRequests.recipientId))
    .leftJoin(activities, eq(activities.id, noteRequests.activityId));
}

type NoteRequestRow = Awaited<ReturnType<ReturnType<typeof selectNoteRequests>["execute"]>>[number];

function toView(row: NoteRequestRow, viewerId: string, now: Date): NoteRequestView {
  const incoming = row.recipient.id === viewerId;
  const location =
    row.replyLatitude != null && row.replyLongitude != null
      ? { latitude: row.replyLatitude, longitude: row.replyLongitude }
      : null;
  return {
    id: row.id,
    direction: incoming ? "INCOMING" : "OUTGOING",
    otherUser: incoming ? row.requester : row.recipient,
    activity: row.activity?.id ? row.activity : null,
    status: row.status,
    isExpired: row.status === "PENDING" && row.expiresAt <= now,
    createdAt: row.createdAt,
    expiresAt: row.expiresAt,
    reply:
      row.status === "ANSWERED" && row.replyText != null && row.respondedAt
        ? { text: row.replyText, placeLabel: row.replyPlaceLabel, location, respondedAt: row.respondedAt }
        : null,
  };
}

// Requests the user sent or received since `since`, newest first. Pass `ids` to fetch specific ones.
export async function listNoteRequestsForUser(
  userId: string,
  { since, ids }: { since: Date; ids?: string[] },
): Promise<NoteRequestView[]> {
  if (ids?.length === 0) return [];
  const rows = await selectNoteRequests()
    .where(
      and(
        or(eq(noteRequests.requesterId, userId), eq(noteRequests.recipientId, userId)),
        gt(noteRequests.createdAt, since),
        ids ? inArray(noteRequests.id, ids) : undefined,
      ),
    )
    .orderBy(desc(noteRequests.createdAt))
    .limit(100);
  const now = new Date();
  return rows.map((row) => toView(row, userId, now));
}

// Sends a request to each recipient, skipping anyone who already has an open one from this user.
export async function createNoteRequests(
  requesterId: string,
  recipientIds: string[],
  activityId: string | null,
): Promise<{ createdIds: string[]; skippedIds: string[] }> {
  const now = new Date();
  const open = await db
    .select({ recipientId: noteRequests.recipientId })
    .from(noteRequests)
    .where(
      and(
        eq(noteRequests.requesterId, requesterId),
        inArray(noteRequests.recipientId, recipientIds),
        eq(noteRequests.status, "PENDING"),
        gt(noteRequests.expiresAt, now),
      ),
    );
  const skippedIds = [...new Set(open.map((row) => row.recipientId))];
  const toCreate = recipientIds.filter((id) => !skippedIds.includes(id));
  if (toCreate.length === 0) return { createdIds: [], skippedIds };

  const expiresAt = new Date(now.getTime() + NOTE_REQUEST_LIFETIME_MS);
  const created = await db
    .insert(noteRequests)
    .values(toCreate.map((recipientId) => ({ requesterId, recipientId, activityId, expiresAt })))
    .returning({ id: noteRequests.id });
  return { createdIds: created.map((row) => row.id), skippedIds };
}

// Only the recipient can answer, and only while the request is pending and unexpired.
// Returns false when there's no such request, or it can't be answered any more.
export async function answerNoteRequest(
  requestId: string,
  recipientId: string,
  answer: { status: "ANSWERED"; reply: ReplyToNoteRequest } | { status: "DECLINED" },
): Promise<boolean> {
  const now = new Date();
  const reply = answer.status === "ANSWERED" ? answer.reply : null;
  const updated = await db
    .update(noteRequests)
    .set({
      status: answer.status,
      replyText: reply?.text ?? null,
      replyPlaceLabel: reply?.placeLabel || null,
      replyGeom: reply?.latitude != null && reply.longitude != null ? { x: reply.longitude, y: reply.latitude } : null,
      respondedAt: now,
      updatedAt: now,
    })
    .where(
      and(
        eq(noteRequests.id, requestId),
        eq(noteRequests.recipientId, recipientId),
        eq(noteRequests.status, "PENDING"),
        gt(noteRequests.expiresAt, now),
      ),
    )
    .returning({ id: noteRequests.id });
  return updated.length > 0;
}

export async function noteRequestExistsForRecipient(requestId: string, recipientId: string): Promise<boolean> {
  const [row] = await db
    .select({ id: noteRequests.id })
    .from(noteRequests)
    .where(and(eq(noteRequests.id, requestId), eq(noteRequests.recipientId, recipientId)))
    .limit(1);
  return Boolean(row);
}
