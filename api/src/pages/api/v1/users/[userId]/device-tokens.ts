import { deleteDeviceToken, saveDeviceToken } from "@/push-service/device-tokens-queries";
import { apiRoute, parseOrReject } from "@/utils/api-response";
import { requireUser } from "@/utils/route-params";
import { deleteDeviceTokenRequestSchema, saveDeviceTokenRequestSchema } from "@/validators/device-tokens";

export default apiRoute({
  // POST /api/v1/users/{userId}/device-tokens — registers this device for push notifications. Sending
  // the same token again is fine; a token registered by someone else moves to this user.
  async POST(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, saveDeviceTokenRequestSchema, req.body);
    if (!body) return;

    await saveDeviceToken(user.id, body.token, body.environment);
    res.status(204).end();
  },

  // DELETE /api/v1/users/{userId}/device-tokens — stops pushes to this device, e.g. on sign-out.
  // Succeeds even if the token wasn't registered, so signing out never fails on it.
  async DELETE(req, res) {
    const user = await requireUser(req, res);
    if (!user) return;
    const body = parseOrReject(res, deleteDeviceTokenRequestSchema, req.body);
    if (!body) return;

    await deleteDeviceToken(user.id, body.token);
    res.status(204).end();
  },
});
