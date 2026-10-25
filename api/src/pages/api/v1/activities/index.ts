import { listStandardActivities } from "@/activities-service/activities-queries";
import { apiRoute } from "@/utils/api-response";

export default apiRoute({
  // GET /api/v1/activities — every standard activity, by name. Not tied to a user, so the app can
  // show the list during registration, before the account exists.
  async GET(_req, res) {
    res.status(200).json({ activities: await listStandardActivities() });
  },
});
