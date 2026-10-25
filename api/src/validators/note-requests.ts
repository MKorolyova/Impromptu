import { z } from "zod";

// Body of POST /api/v1/users/{userId}/note-requests.
export const createNoteRequestsSchema = z.object({
  recipientIds: z.array(z.uuid()).min(1).max(10),
});

// Body of POST /api/v1/users/{userId}/note-requests/{requestId}/reply.
// latitude and longitude come together or not at all.
export const replyToNoteRequestSchema = z
  .object({
    text: z.string().trim().min(1).max(280),
    placeLabel: z.string().trim().max(100).nullish(),
    latitude: z.number().min(-90).max(90).nullish(),
    longitude: z.number().min(-180).max(180).nullish(),
  })
  .refine((reply) => (reply.latitude == null) === (reply.longitude == null), {
    message: "latitude and longitude must be sent together",
    path: ["latitude"],
  });

export type ReplyToNoteRequest = z.infer<typeof replyToNoteRequestSchema>;
