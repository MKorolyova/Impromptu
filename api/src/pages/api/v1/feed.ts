import { getCurrentStatuses } from "@/statuses-service/statuses-queries";
import { listUserProfiles } from "@/users-service/users-queries";
import { apiRoute } from "@/utils/api-response";

export default apiRoute({
  // GET /api/v1/feed — everyone's public profile with their current status.
  // People with a status come first, most recently started first; then everyone else by name.
  async GET(_req, res) {
    const profiles = await listUserProfiles();
    const statuses = await getCurrentStatuses(profiles.map((profile) => profile.id));
    const users = profiles
      .map((profile) => ({ ...profile, status: statuses.get(profile.id) ?? null }))
      .sort((a, b) => (b.status?.startedAt.getTime() ?? 0) - (a.status?.startedAt.getTime() ?? 0));
    res.status(200).json({ users });
  },
});
