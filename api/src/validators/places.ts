import { z } from "zod";
import { places } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema, generatedColumns } from "./schema-factory.ts";

export const placeSchema = createSelectSchema(places);

export const createPlaceSchema = createInsertSchema(places, {
  label: (s) => s.trim().min(1).max(50),
  // x is longitude, y is latitude (SRID 4326).
  geom: () => z.object({ x: z.number().min(-180).max(180), y: z.number().min(-90).max(90) }),
  radiusMeters: (s) => s.positive().max(50_000),
}).omit(generatedColumns);

export type Place = z.infer<typeof placeSchema>;
export type CreatePlaceInput = z.infer<typeof createPlaceSchema>;
