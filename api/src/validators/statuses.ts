import { z } from "zod";
import { statuses } from "@/db/schema";
import { createInsertSchema, createSelectSchema, softDeletableColumns } from "@/validators/schema-factory";

export const statusSchema = createSelectSchema(statuses);

export const createStatusSchema = createInsertSchema(statuses, {
  note: (s) => s.trim().max(280),
})
  .omit(softDeletableColumns)
  .refine((s) => s.expiresAt > (s.startedAt ?? new Date()), {
    message: "expiresAt must be after startedAt",
    path: ["expiresAt"],
  });

// Body of POST /api/v1/users/{userId}/statuses. expiresAt defaults to now + the activity's duration.
export const createStatusRequestSchema = z.object({
  activityId: z.uuid(),
  note: z.string().trim().max(280).nullish(),
  expiresAt: z.coerce
    .date()
    .refine((date) => date > new Date(), "expiresAt must be in the future")
    .optional(),
});

export type Status = z.infer<typeof statusSchema>;
export type CreateStatusInput = z.infer<typeof createStatusSchema>;
export type CreateStatusRequest = z.infer<typeof createStatusRequestSchema>;
