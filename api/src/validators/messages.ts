import { z } from "zod";
import { messages } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema, generatedColumns } from "./schema-factory.ts";

export const messageSchema = createSelectSchema(messages);

export const createMessageSchema = createInsertSchema(messages, {
  body: (s) => s.trim().min(1).max(4000),
}).omit({ ...generatedColumns, readAt: true });

export type Message = z.infer<typeof messageSchema>;
export type CreateMessageInput = z.infer<typeof createMessageSchema>;
