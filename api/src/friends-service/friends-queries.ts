import { and, asc, eq, isNull } from "drizzle-orm";
import { db } from "@/db/index";
import { friendships, users } from "@/db/schema";
import type { UserProfile } from "@/users-service/users-queries";
import type { FriendAccess } from "@/validators/friendships";

// Someone the user added, and what the user lets them see.
export type Friend = UserProfile & { canSeeLocation: boolean; canSeeNotes: boolean };

const friendColumns = {
  id: users.id,
  firstName: users.firstName,
  lastName: users.lastName,
  nickname: users.nickname,
  canSeeLocation: friendships.canSeeLocation,
  canSeeNotes: friendships.canSeeNotes,
};

const isFriendOf = (userId: string, friendId: string) =>
  and(eq(friendships.userId, userId), eq(friendships.friendId, friendId));

// Friends whose accounts still exist, by name.
export function listFriends(userId: string): Promise<Friend[]> {
  return db
    .select(friendColumns)
    .from(friendships)
    .innerJoin(users, eq(friendships.friendId, users.id))
    .where(and(eq(friendships.userId, userId), isNull(users.deletedAt)))
    .orderBy(asc(users.firstName), asc(users.lastName));
}

export async function getFriend(userId: string, friendId: string): Promise<Friend | null> {
  const [friend] = await db
    .select(friendColumns)
    .from(friendships)
    .innerJoin(users, eq(friendships.friendId, users.id))
    .where(and(isFriendOf(userId, friendId), isNull(users.deletedAt)))
    .limit(1);
  return friend ?? null;
}

// Adds a friend, or changes what an existing one can see. Someone new can see nothing unless `access` says so.
export async function addFriend(userId: string, friendId: string, access: FriendAccess): Promise<void> {
  const insert = db.insert(friendships).values({ userId, friendId, ...access });
  if (Object.keys(access).length === 0) {
    await insert.onConflictDoNothing();
    return;
  }
  await insert.onConflictDoUpdate({
    target: [friendships.userId, friendships.friendId],
    set: { ...access, updatedAt: new Date() },
  });
}

// Returns false when friendId isn't one of the user's friends.
export async function updateFriendAccess(userId: string, friendId: string, access: FriendAccess): Promise<boolean> {
  const updated = await db
    .update(friendships)
    .set(access)
    .where(isFriendOf(userId, friendId))
    .returning({ friendId: friendships.friendId });
  return updated.length > 0;
}

// Returns false when friendId isn't one of the user's friends.
export async function removeFriend(userId: string, friendId: string): Promise<boolean> {
  const removed = await db
    .delete(friendships)
    .where(isFriendOf(userId, friendId))
    .returning({ friendId: friendships.friendId });
  return removed.length > 0;
}
