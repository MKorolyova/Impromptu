import { z } from "zod";

// Body of PUT /api/v1/users/{userId}/location.
export const updateLocationRequestSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracyMeters: z.number().nonnegative().max(100_000).nullish(),
});

// Query of GET /api/v1/users/{userId}/nearby. Defaults to about a mile.
export const nearbyQuerySchema = z.object({
  radiusMeters: z.coerce.number().int().min(50).max(50_000).default(1600),
});

export type UpdateLocationRequest = z.infer<typeof updateLocationRequestSchema>;
