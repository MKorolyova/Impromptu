import { z } from "zod";
import { conversations } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema, generatedColumns } from "./schema-factory.ts";

export const conversationSchema = createSelectSchema(conversations);

export const createConversationSchema = createInsertSchema(conversations)
  .omit(generatedColumns)
  .refine((c) => c.userAId < c.userBId, {
    message: "userAId must sort before userBId",
    path: ["userBId"],
  });

export type Conversation = z.infer<typeof conversationSchema>;
export type CreateConversationInput = z.infer<typeof createConversationSchema>;
