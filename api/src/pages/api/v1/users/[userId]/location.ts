import { deleteUserLocation, upsertUserLocation } from "@/locations-service/locations-queries";
import { announceNearbyMatchesLater } from "@/locations-service/nearby-alerts";
import { apiRoute, parseOrReject } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { updateLocationRequestSchema } from "@/validators/locations";

export default apiRoute({
  // PUT /api/v1/users/{userId}/location — the user's current position, for finding people nearby. Anyone
  // the move brings within 3 miles who's doing the same activity gets a push, and so does the user.
  async PUT(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, updateLocationRequestSchema, req.body);
    if (!body) return;

    await upsertUserLocation(user.id, body);
    res.status(204).end();
    announceNearbyMatchesLater(user.id);
  },

  // DELETE /api/v1/users/{userId}/location — stops sharing; the position is removed, not soft-deleted.
  async DELETE(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    await deleteUserLocation(user.id);
    res.status(204).end();
  },
});
