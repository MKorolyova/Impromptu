import { and, eq, isNull } from "drizzle-orm";
import { db } from "@/db/index";
import { users } from "@/db/schema";
import type { CreateUserInput } from "@/validators/users";

// Every column except passwordHash and deletedAt; safe to return from the API.
const publicUserColumns = {
  id: users.id,
  email: users.email,
  firstName: users.firstName,
  lastName: users.lastName,
  nickname: users.nickname,
  timezone: users.timezone,
  createdAt: users.createdAt,
  updatedAt: users.updatedAt,
};

export type PublicUser = {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  nickname: string | null;
  timezone: string;
  createdAt: Date;
  updatedAt: Date;
};

const isActiveUser = (userId: string) => and(eq(users.id, userId), isNull(users.deletedAt));

export async function createUser(input: CreateUserInput): Promise<PublicUser> {
  const [user] = await db.insert(users).values(input).returning(publicUserColumns);
  return user;
}

export async function getUserById(userId: string): Promise<PublicUser | null> {
  const [user] = await db.select(publicUserColumns).from(users).where(isActiveUser(userId)).limit(1);
  return user ?? null;
}

// Returns false when the user doesn't exist or was already deleted.
export async function softDeleteUser(userId: string): Promise<boolean> {
  const deleted = await db
    .update(users)
    .set({ deletedAt: new Date() })
    .where(isActiveUser(userId))
    .returning({ id: users.id });
  return deleted.length > 0;
}
