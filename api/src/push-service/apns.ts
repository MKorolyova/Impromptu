import { createPrivateKey } from "node:crypto";
import { connect, type ClientHttp2Session } from "node:http2";
import { env } from "@/env";
import {
  APNS_HOSTS,
  apnsPayload,
  classifyApnsResponse,
  createApnsToken,
  readReason,
  type ApnsCredentials,
  type ApnsOutcome,
  type PushEnvironmentValue,
  type PushMessage,
} from "@/push-service/apns-protocol";

// Apple wants a new provider token at most every 20 minutes and rejects ones over an hour old.
const PROVIDER_TOKEN_LIFETIME_MS = 40 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 10_000;
// A nearby alert is stale after this; APNs drops it rather than delivering it late.
const PUSH_LIFETIME_SECONDS = 30 * 60;

type ApnsConfig = ApnsCredentials & { topic: string };

export type PushDelivery = { token: string; environment: PushEnvironmentValue; message: PushMessage };

export type PushResult = {
  token: string;
  outcome: Exclude<ApnsOutcome, "WRONG_ENVIRONMENT">;
  // Where the token turned out to belong, which can differ from what the app reported.
  environment: PushEnvironmentValue;
};

// Read once; null when APNs isn't set up, in which case nothing is sent.
let config: ApnsConfig | null | undefined;
let providerToken: { value: string; issuedAt: number } | null = null;

function getConfig(): ApnsConfig | null {
  if (config !== undefined) return config;
  const { APNS_KEY_ID: keyId, APNS_TEAM_ID: teamId, APNS_PRIVATE_KEY: key, APNS_BUNDLE_ID: topic } = env;
  if (!keyId || !teamId || !key || !topic) {
    console.warn("APNs isn't configured (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID); push notifications are off");
    config = null;
    return config;
  }
  try {
    config = { keyId, teamId, topic, privateKey: createPrivateKey(key.replace(/\\n/g, "\n")) };
  } catch {
    console.error("APNS_PRIVATE_KEY isn't a valid .p8 key; push notifications are off");
    config = null;
  }
  return config;
}

function getProviderToken(config: ApnsConfig): string {
  const now = Date.now();
  if (!providerToken || now - providerToken.issuedAt > PROVIDER_TOKEN_LIFETIME_MS) {
    providerToken = { value: createApnsToken(config, new Date(now)), issuedAt: now };
  }
  return providerToken.value;
}

const otherEnvironment = (environment: PushEnvironmentValue): PushEnvironmentValue =>
  environment === "SANDBOX" ? "PRODUCTION" : "SANDBOX";

// Sends every push, over one HTTP/2 connection per APNs server. A token APNs says belongs to the
// other server is retried there once. Returns nothing when APNs isn't configured.
export async function sendPushes(deliveries: PushDelivery[]): Promise<PushResult[]> {
  const config = getConfig();
  if (!config || deliveries.length === 0) return [];

  const sessions = new Map<PushEnvironmentValue, ClientHttp2Session>();
  const sessionFor = (environment: PushEnvironmentValue) => {
    let session = sessions.get(environment);
    if (!session || session.closed || session.destroyed) {
      session = connect(APNS_HOSTS[environment]);
      // Failures also reach each request, which reports them; this keeps them from crashing the server.
      session.on("error", (error) => console.error(`APNs connection failed: ${error.message}`));
      sessions.set(environment, session);
    }
    return session;
  };

  try {
    return await Promise.all(
      deliveries.map(async ({ token, environment, message }): Promise<PushResult> => {
        const first = await post(sessionFor(environment), config, token, message);
        if (first !== "WRONG_ENVIRONMENT") return { token, outcome: first, environment };
        const retryEnvironment = otherEnvironment(environment);
        const retry = await post(sessionFor(retryEnvironment), config, token, message);
        return {
          token,
          outcome: retry === "WRONG_ENVIRONMENT" ? "INVALID_TOKEN" : retry,
          environment: retryEnvironment,
        };
      }),
    );
  } finally {
    for (const session of sessions.values()) session.close();
  }
}

// One push. Never logs the token, which is in the path.
function post(session: ClientHttp2Session, config: ApnsConfig, token: string, message: PushMessage): Promise<ApnsOutcome> {
  return new Promise((resolve) => {
    const request = session.request({
      ":method": "POST",
      ":path": `/3/device/${token}`,
      authorization: `bearer ${getProviderToken(config)}`,
      "apns-topic": config.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + PUSH_LIFETIME_SECONDS),
      "content-type": "application/json",
    });
    let status = 0;
    let body = "";
    request.setEncoding("utf8");
    request.on("response", (headers) => {
      status = Number(headers[":status"]);
    });
    request.on("data", (chunk: string) => {
      body += chunk;
    });
    request.on("error", (error) => console.error(`APNs request failed: ${error.message}`));
    request.setTimeout(REQUEST_TIMEOUT_MS, () => request.close());
    // Emitted last in every case: answered, failed or timed out.
    request.on("close", () => {
      const outcome = classifyApnsResponse(status, body);
      if (outcome === "FAILED" && status !== 0) {
        console.error(`APNs rejected a push: ${status} ${readReason(body) ?? ""}`.trim());
      }
      resolve(outcome);
    });
    request.end(JSON.stringify(apnsPayload(message)));
  });
}
