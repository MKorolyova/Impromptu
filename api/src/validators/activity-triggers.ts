import { z } from "zod";
import { activityTriggers } from "@/db/schema";
import { createInsertSchema, createSelectSchema, generatedColumns } from "@/validators/schema-factory";

export const activityTriggerSchema = createSelectSchema(activityTriggers);

export const createActivityTriggerSchema = createInsertSchema(activityTriggers, {
  config: () => z.record(z.string(), z.unknown()),
}).omit(generatedColumns);

export type ActivityTrigger = z.infer<typeof activityTriggerSchema>;
export type CreateActivityTriggerInput = z.infer<typeof createActivityTriggerSchema>;
