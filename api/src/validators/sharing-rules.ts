import { z } from "zod";
import { sharingRules } from "@/db/schema";
import { createInsertSchema, createSelectSchema, generatedColumns } from "@/validators/schema-factory";

export const sharingRuleSchema = createSelectSchema(sharingRules);

export const createSharingRuleSchema = createInsertSchema(sharingRules).omit(generatedColumns);

export type SharingRule = z.infer<typeof sharingRuleSchema>;
export type CreateSharingRuleInput = z.infer<typeof createSharingRuleSchema>;
