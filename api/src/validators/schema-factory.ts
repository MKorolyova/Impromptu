import { createSchemaFactory } from "drizzle-zod";

// JSON bodies carry timestamps as ISO strings, so dates are coerced.
export const { createSelectSchema, createInsertSchema } = createSchemaFactory({
  coerce: { date: true },
});

// Columns the database fills in; never accepted from a client.
export const generatedColumns = {
  id: true,
  createdAt: true,
  updatedAt: true,
} as const;
