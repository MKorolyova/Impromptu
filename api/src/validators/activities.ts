import { z } from "zod";
import { ACTIVITIES } from "../constants/activities.ts";
import { activities } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema, generatedColumns } from "./schema-factory.ts";

const standardActivityNames = new Set(ACTIVITIES.map((activity) => activity.name));

export const activitySchema = createSelectSchema(activities);

export const createActivitySchema = createInsertSchema(activities, {
  name: (s) => s.trim().min(1).max(50),
  defaultDurationMinutes: (s) => s.positive(),
})
  .omit(generatedColumns)
  .superRefine((a, ctx) => {
    if (a.isCustom) {
      if (a.ownerId == null) {
        ctx.addIssue({ code: "custom", message: "Custom activities need an owner", path: ["ownerId"] });
      }
      return;
    }
    if (!standardActivityNames.has(a.name)) {
      ctx.addIssue({code: "custom", message: "Not a standard activity; set isCustom to true to create your own", path: ["name"]});
    }
    if (a.ownerId != null) {
      ctx.addIssue({ code: "custom", message: "Standard activities have no owner", path: ["ownerId"] });
    }
  });

export type Activity = z.infer<typeof activitySchema>;
export type CreateActivityInput = z.infer<typeof createActivitySchema>;
