import { z } from "zod";
import { sharingRules } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema, generatedColumns } from "./schema-factory.ts";

export const sharingRuleSchema = createSelectSchema(sharingRules);

export const createSharingRuleSchema = createInsertSchema(sharingRules).omit(generatedColumns);

export type SharingRule = z.infer<typeof sharingRuleSchema>;
export type CreateSharingRuleInput = z.infer<typeof createSharingRuleSchema>;
