import { z } from "zod";
import { statuses } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema, generatedColumns } from "./schema-factory.ts";

export const statusSchema = createSelectSchema(statuses);

export const createStatusSchema = createInsertSchema(statuses, {
  note: (s) => s.trim().max(280),
})
  .omit(generatedColumns)
  .refine((s) => s.expiresAt > (s.startedAt ?? new Date()), {
    message: "expiresAt must be after startedAt",
    path: ["expiresAt"],
  });

export type Status = z.infer<typeof statusSchema>;
export type CreateStatusInput = z.infer<typeof createStatusSchema>;
