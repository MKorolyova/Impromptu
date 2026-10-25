import { sendPushes } from "@/push-service/apns";
import type { PushMessage } from "@/push-service/apns-protocol";
import {
  deleteDeviceTokens,
  listDeviceTokens,
  updateDeviceTokenEnvironment,
} from "@/push-service/device-tokens-queries";

// Sends each user their message on every device they've registered; users without one get nothing.
// Afterwards forgets tokens APNs rejected and remembers which server the others really belong to.
export async function pushToUsers(messages: { userId: string; message: PushMessage }[]): Promise<void> {
  const messageByUser = new Map(messages.map(({ userId, message }) => [userId, message]));
  const tokens = await listDeviceTokens([...messageByUser.keys()]);
  const deliveries = tokens.flatMap(({ token, userId, environment }) => {
    const message = messageByUser.get(userId);
    return message ? [{ token, environment, message }] : [];
  });

  const results = await sendPushes(deliveries);
  const reportedEnvironment = new Map(tokens.map(({ token, environment }) => [token, environment]));
  await deleteDeviceTokens(results.filter((result) => result.outcome === "INVALID_TOKEN").map((result) => result.token));
  await Promise.all(
    results
      .filter((result) => result.outcome === "SENT" && result.environment !== reportedEnvironment.get(result.token))
      .map((result) => updateDeviceTokenEnvironment(result.token, result.environment)),
  );
}
