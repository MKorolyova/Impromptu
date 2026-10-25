import { z } from "zod";
import { friendships } from "@/db/schema";
import { createInsertSchema, createSelectSchema } from "@/validators/schema-factory";

export const friendshipSchema = createSelectSchema(friendships);

export const createFriendshipSchema = createInsertSchema(friendships)
  .omit({ createdAt: true, updatedAt: true })
  .refine((f) => f.userId !== f.friendId, {
    message: "A user cannot be friends with themselves",
    path: ["friendId"],
  });

// What the user lets a friend see. Fields left out keep their current value.
const friendAccessSchema = z.object({ canSeeLocation: z.boolean(), canSeeNotes: z.boolean() }).partial();

// Body of POST /api/v1/users/{userId}/friends: who to add, by email or by user ID (as two phones held
// together exchange), always in the body, never the URL.
export const addFriendRequestSchema = friendAccessSchema
  .extend({
    email: z.string().trim().toLowerCase().pipe(z.email()).optional(),
    friendId: z.uuid().optional(),
  })
  .refine((body) => (body.email === undefined) !== (body.friendId === undefined), {
    message: "Send either email or friendId",
    path: ["email"],
  });

// Body of PATCH /api/v1/users/{userId}/friends/{friendId}.
export const updateFriendRequestSchema = friendAccessSchema.refine(
  (body) => Object.keys(body).length > 0,
  "Send canSeeLocation, canSeeNotes or both",
);

export type Friendship = z.infer<typeof friendshipSchema>;
export type CreateFriendshipInput = z.infer<typeof createFriendshipSchema>;
export type FriendAccess = z.infer<typeof friendAccessSchema>;
export type AddFriendRequest = z.infer<typeof addFriendRequestSchema>;
