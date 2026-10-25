import type { NextApiRequest, NextApiResponse } from "next";
import {
  answerNoteRequest,
  listNoteRequestsForUser,
  NOTE_REQUEST_LIFETIME_MS,
  noteRequestExistsForRecipient,
} from "@/note-requests-service/note-requests-queries";
import { sendError } from "@/utils/api-response";
import { readIdParam, requireUser } from "@/utils/route-params";
import type { ReplyToNoteRequest } from "@/validators/note-requests";

// Shared by the reply and decline routes: answers as the recipient and returns the updated request.
export async function respondToNoteRequest(
  req: NextApiRequest,
  res: NextApiResponse,
  answer: { status: "ANSWERED"; reply: ReplyToNoteRequest } | { status: "DECLINED" },
): Promise<void> {
  const user = await requireUser(req, res);
  if (!user) return;
  const requestId = readIdParam(req, res, "requestId");
  if (!requestId) return;

  if (!(await answerNoteRequest(requestId, user.id, answer))) {
    if (!(await noteRequestExistsForRecipient(requestId, user.id))) {
      return sendError(res, "NOT_FOUND", "Note request not found");
    }
    return sendError(res, "CONFLICT", "This request was already answered or has expired");
  }
  const [request] = await listNoteRequestsForUser(user.id, {
    since: new Date(Date.now() - NOTE_REQUEST_LIFETIME_MS),
    ids: [requestId],
  });
  res.status(200).json({ request });
}
