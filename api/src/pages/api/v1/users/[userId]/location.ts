import { deleteUserLocation, upsertUserLocation } from "@/locations-service/locations-queries";
import { apiRoute, parseOrReject } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { updateLocationRequestSchema } from "@/validators/locations";

export default apiRoute({
  // PUT /api/v1/users/{userId}/location — the user's current position, for finding people nearby.
  async PUT(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, updateLocationRequestSchema, req.body);
    if (!body) return;

    await upsertUserLocation(user.id, body);
    res.status(204).end();
  },

  // DELETE /api/v1/users/{userId}/location — stops sharing; the position is removed, not soft-deleted.
  async DELETE(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    await deleteUserLocation(user.id);
    res.status(204).end();
  },
});
