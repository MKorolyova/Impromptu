import { findNearbyMatches } from "@/locations-service/nearby";
import {
  createNoteRequests,
  listNoteRequestsForUser,
  NOTE_REQUEST_LIFETIME_MS,
} from "@/note-requests-service/note-requests-queries";
import { apiRoute, parseOrReject, sendError } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { nearbyQuerySchema } from "@/validators/locations";
import { createNoteRequestsSchema } from "@/validators/note-requests";

// Requests older than this drop out of the inbox.
const INBOX_WINDOW_MS = 24 * 60 * 60 * 1000;

export default apiRoute({
  // GET /api/v1/users/{userId}/note-requests — the past day's requests, split into received and sent.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const requests = await listNoteRequestsForUser(user.id, { since: new Date(Date.now() - INBOX_WINDOW_MS) });
    res.status(200).json({
      incoming: requests.filter((request) => request.direction === "INCOMING"),
      outgoing: requests.filter((request) => request.direction === "OUTGOING"),
    });
  },

  // POST /api/v1/users/{userId}/note-requests — asks people nearby for a note. Each recipient must be
  // nearby and doing the same activity right now, so this can't be used to message anyone else.
  async POST(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, createNoteRequestsSchema, req.body);
    if (!body) return;
    const { radiusMeters } = nearbyQuerySchema.parse({});

    const { activity, matches } = await findNearbyMatches(user.id, radiusMeters);
    if (!activity) return sendError(res, "FORBIDDEN", "Set a status before asking people nearby for a note");
    const nearbyIds = new Set(matches.map((match) => match.id));
    const recipientIds = [...new Set(body.recipientIds)];
    const notNearby = recipientIds.filter((id) => !nearbyIds.has(id));
    if (notNearby.length > 0) {
      return sendError(res, "FORBIDDEN", "You can only ask people who are nearby and doing the same thing");
    }

    const { createdIds, skippedIds } = await createNoteRequests(user.id, recipientIds, activity.id);
    const requests = await listNoteRequestsForUser(user.id, {
      since: new Date(Date.now() - NOTE_REQUEST_LIFETIME_MS),
      ids: createdIds,
    });
    // skippedRecipientIds already have an open request from you.
    res.status(201).json({ requests, skippedRecipientIds: skippedIds });
  },
});
