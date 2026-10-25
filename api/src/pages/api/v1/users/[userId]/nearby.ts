import { findNearbyMatches } from "@/locations-service/nearby";
import { apiRoute, parseOrReject } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { nearbyQuerySchema } from "@/validators/locations";

export default apiRoute({
  // GET /api/v1/users/{userId}/nearby[?radiusMeters=1600] — people within the radius doing the same
  // activity as the user right now, closest first. Distances are rounded up to 100 m; positions are never returned.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const query = parseOrReject(res, nearbyQuerySchema, req.query);
    if (!query) return;

    const { activity, matches } = await findNearbyMatches(user.id, query.radiusMeters);
    res.status(200).json({ activity, radiusMeters: query.radiusMeters, users: matches });
  },
});
