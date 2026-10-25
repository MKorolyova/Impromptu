import { findNearbyUserIds } from "@/locations-service/locations-queries";
import { getCurrentStatuses } from "@/statuses-service/statuses-queries";
import { getUserProfilesByIds } from "@/users-service/users-queries";
import { apiRoute, parseOrReject } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { nearbyQuerySchema } from "@/validators/locations";

// Positions older than this are treated as unknown, so people who stopped sharing drop off.
const LOCATION_MAX_AGE_MS = 2 * 60 * 60 * 1000;

export default apiRoute({
  // GET /api/v1/users/{userId}/nearby[?radiusMeters=1600] — people within the radius doing the same
  // activity as the user right now. Never includes anyone's position or distance.
  async GET(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const query = parseOrReject(res, nearbyQuerySchema, req.query);
    if (!query) return;

    const myStatus = (await getCurrentStatuses([user.id])).get(user.id);
    if (!myStatus) return res.status(200).json({ activity: null, radiusMeters: query.radiusMeters, users: [] });

    const nearbyIds = await findNearbyUserIds(user.id, {
      radiusMeters: query.radiusMeters,
      freshSince: new Date(Date.now() - LOCATION_MAX_AGE_MS),
    });
    const statuses = await getCurrentStatuses(nearbyIds);
    const matchingIds = nearbyIds.filter((id) => statuses.get(id)?.activity.id === myStatus.activity.id);
    const users = (await getUserProfilesByIds(matchingIds))
      .map((profile) => ({ ...profile, status: statuses.get(profile.id)! }))
      .sort((a, b) => b.status.startedAt.getTime() - a.status.startedAt.getTime());

    res.status(200).json({ activity: myStatus.activity, radiusMeters: query.radiusMeters, users });
  },
});
