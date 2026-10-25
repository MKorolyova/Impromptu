import { sign, type KeyObject } from "node:crypto";

// The parts of talking to APNs that don't need a network, kept apart so they can be tested.

export type PushEnvironmentValue = "SANDBOX" | "PRODUCTION";

export type PushMessage = {
  title: string;
  body: string;
  // The app screen a tap opens, as the app's AppRoute names it. Also groups notifications.
  route: string;
};

export type ApnsCredentials = { keyId: string; teamId: string; privateKey: KeyObject };

// What an APNs response means for the device token it was sent to.
export type ApnsOutcome =
  | "SENT"
  // A sandbox token sent to production or the reverse; worth trying the other server.
  | "WRONG_ENVIRONMENT"
  // The app was deleted, or the token is for another app; the token should be forgotten.
  | "INVALID_TOKEN"
  | "FAILED";

export const APNS_HOSTS: Record<PushEnvironmentValue, string> = {
  PRODUCTION: "https://api.push.apple.com",
  SANDBOX: "https://api.sandbox.push.apple.com",
};

// The provider token: an ES256 JWT naming the key and team. Apple accepts one for up to an hour.
export function createApnsToken({ keyId, teamId, privateKey }: ApnsCredentials, issuedAt: Date): string {
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid: keyId })}.${encode({
    iss: teamId,
    iat: Math.floor(issuedAt.getTime() / 1000),
  })}`;
  // APNs wants the raw 64-byte signature, not the DER encoding Node produces by default.
  const signature = sign("sha256", Buffer.from(unsigned), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${signature.toString("base64url")}`;
}

// The JSON body of one push. `route` sits next to `aps`, where the app reads it when the push is tapped.
export function apnsPayload({ title, body, route }: PushMessage): object {
  return { aps: { alert: { title, body }, sound: "default", "thread-id": route }, route };
}

export function classifyApnsResponse(status: number, responseBody: string): ApnsOutcome {
  if (status === 200) return "SENT";
  const reason = readReason(responseBody);
  if (status === 400 && reason === "BadDeviceToken") return "WRONG_ENVIRONMENT";
  if (status === 410 || (status === 400 && reason === "DeviceTokenNotForTopic")) return "INVALID_TOKEN";
  return "FAILED";
}

// APNs explains failures as {"reason": "..."}.
export function readReason(responseBody: string): string | undefined {
  try {
    const reason = (JSON.parse(responseBody) as { reason?: unknown }).reason;
    return typeof reason === "string" ? reason : undefined;
  } catch {
    return undefined;
  }
}
