import { respondToNoteRequest } from "@/note-requests-service/answer-route";
import { apiRoute } from "@/utils/api-response";

export default apiRoute({
  // POST /api/v1/users/{userId}/note-requests/{requestId}/decline — the recipient says no.
  async POST(req, res) {
    await respondToNoteRequest(req, res, { status: "DECLINED" });
  },
});
