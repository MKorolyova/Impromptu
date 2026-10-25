import { z } from "zod";
import { calendarLinks } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema } from "./schema-factory.ts";

export const calendarLinkSchema = createSelectSchema(calendarLinks);

export const createCalendarLinkSchema = createInsertSchema(calendarLinks, {
  encryptedRefreshToken: (s) => s.min(1),
}).omit({ createdAt: true, updatedAt: true });

export type CalendarLink = z.infer<typeof calendarLinkSchema>;
export type CreateCalendarLinkInput = z.infer<typeof createCalendarLinkSchema>;
