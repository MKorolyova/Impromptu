import { ACTIVITIES } from "@/constants/activities";
import { apiRoute } from "@/utils/api-response";

export default apiRoute({
  // GET /api/v1/activities — every standard activity, straight from constants/activities.ts (no
  // database). Not tied to a user, so the app can show the list during registration.
  async GET(_req, res) {
    res.status(200).json({ activities: ACTIVITIES });
  },
});
