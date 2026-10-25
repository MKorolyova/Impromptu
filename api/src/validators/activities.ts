import { z } from "zod";
import { ACTIVITIES } from "@/constants/activities";
import { activities } from "@/db/schema";
import { createInsertSchema, createSelectSchema, softDeletableColumns } from "@/validators/schema-factory";

const standardActivityNames = new Set(ACTIVITIES.map((activity) => activity.name));

export const activitySchema = createSelectSchema(activities);

export const createActivitySchema = createInsertSchema(activities, {
  name: (s) => s.trim().min(1).max(50),
  defaultDurationMinutes: (s) => s.positive(),
})
  .omit(softDeletableColumns)
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

// Body of POST /api/v1/users/{userId}/activities. Users can only add custom activities.
export const createCustomActivityRequestSchema = z.object({
  name: z.string().trim().min(1).max(50),
  defaultDurationMinutes: z.int().positive().max(24 * 60),
});

// Body of PUT /api/v1/users/{userId}/saved-activities. Duplicates are ignored.
// `activityIds` are database rows (the user's own activities); `standardActivityNames` are names from
// GET /api/v1/activities, which have no ids until someone uses them.
export const replaceSavedActivitiesRequestSchema = z
  .object({
    activityIds: z
      .array(z.uuid())
      .max(200)
      .default([])
      .transform((ids) => [...new Set(ids.map((id) => id.toLowerCase()))]),
    standardActivityNames: z
      .array(z.string().trim().min(1))
      .max(200)
      .default([])
      .transform((names) => [...new Set(names)]),
  })
  .refine((body) => body.activityIds.length + body.standardActivityNames.length > 0, {
    message: "Pick at least one activity",
    path: ["activityIds"],
  });

export type Activity = z.infer<typeof activitySchema>;
export type CreateActivityInput = z.infer<typeof createActivitySchema>;
export type CreateCustomActivityRequest = z.infer<typeof createCustomActivityRequestSchema>;
export type ReplaceSavedActivitiesRequest = z.infer<typeof replaceSavedActivitiesRequestSchema>;
