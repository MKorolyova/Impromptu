import { respondToNoteRequest } from "@/note-requests-service/answer-route";
import { apiRoute, parseOrReject } from "@/utils/api-response";
import { replyToNoteRequestSchema } from "@/validators/note-requests";

export default apiRoute({
  // POST /api/v1/users/{userId}/note-requests/{requestId}/reply — the recipient answers with a note,
  // and optionally a place and their position.
  async POST(req, res) {
    const reply = parseOrReject(res, replyToNoteRequestSchema, req.body);
    if (!reply) return;
    await respondToNoteRequest(req, res, { status: "ANSWERED", reply });
  },
});
