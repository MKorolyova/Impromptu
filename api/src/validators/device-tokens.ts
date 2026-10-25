import { z } from "zod";
import { PushEnvironment } from "@/db/schema";

// APNs device tokens are hex; 32 bytes today, but Apple says not to rely on the length.
const deviceTokenSchema = z
  .string()
  .regex(/^[0-9a-fA-F]{64,200}$/, "Must be the APNs device token in hex")
  .transform((token) => token.toLowerCase());

// Body of POST /api/v1/users/{userId}/device-tokens.
export const saveDeviceTokenRequestSchema = z.object({
  token: deviceTokenSchema,
  environment: z.enum(PushEnvironment.enumValues),
});

// Body of DELETE /api/v1/users/{userId}/device-tokens. The token goes in the body to keep it out of URLs and logs.
export const deleteDeviceTokenRequestSchema = z.object({
  token: deviceTokenSchema,
});

export type SaveDeviceTokenRequest = z.infer<typeof saveDeviceTokenRequestSchema>;
