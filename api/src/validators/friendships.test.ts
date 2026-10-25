import assert from "node:assert/strict";
import { test } from "node:test";
import { addFriendRequestSchema } from "./friendships.ts";

const friendId = "7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11";

test("adds by email or by user ID", () => {
  assert.deepEqual(addFriendRequestSchema.parse({ email: " Priya@Example.com " }), { email: "priya@example.com" });
  assert.deepEqual(addFriendRequestSchema.parse({ friendId, canSeeLocation: true, canSeeNotes: true }), {
    friendId,
    canSeeLocation: true,
    canSeeNotes: true,
  });
});

test("needs exactly one of them", () => {
  assert.equal(addFriendRequestSchema.safeParse({}).success, false);
  assert.equal(addFriendRequestSchema.safeParse({ email: "priya@example.com", friendId }).success, false);
  assert.equal(addFriendRequestSchema.safeParse({ friendId: "not-a-uuid" }).success, false);
});
