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

export type Friendship = z.infer<typeof friendshipSchema>;
export type CreateFriendshipInput = z.infer<typeof createFriendshipSchema>;
