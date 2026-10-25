import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { test } from "node:test";
import { apnsPayload, classifyApnsResponse, createApnsToken } from "./apns-protocol.ts";

test("provider token is an ES256 JWT that verifies with the key", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const issuedAt = new Date("2026-10-25T18:00:00Z");
  const token = createApnsToken({ keyId: "ABC123DEFG", teamId: "TEAM123456", privateKey }, issuedAt);

  const [header, claims, signature] = token.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url").toString()), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(JSON.parse(Buffer.from(claims, "base64url").toString()), {
    iss: "TEAM123456",
    iat: issuedAt.getTime() / 1000,
  });
  const rawSignature = Buffer.from(signature, "base64url");
  assert.equal(rawSignature.length, 64);
  assert.ok(
    verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, rawSignature),
  );
});

test("payload carries the alert and the route the app opens", () => {
  assert.deepEqual(apnsPayload({ title: "Sam is nearby", body: "Sam is also running within 3 miles.", route: "nearbyPeople" }), {
    aps: {
      alert: { title: "Sam is nearby", body: "Sam is also running within 3 miles." },
      sound: "default",
      "thread-id": "nearbyPeople",
    },
    route: "nearbyPeople",
  });
});

test("responses map to what happens to the token", () => {
  assert.equal(classifyApnsResponse(200, ""), "SENT");
  assert.equal(classifyApnsResponse(400, '{"reason":"BadDeviceToken"}'), "WRONG_ENVIRONMENT");
  assert.equal(classifyApnsResponse(410, '{"reason":"Unregistered"}'), "INVALID_TOKEN");
  assert.equal(classifyApnsResponse(400, '{"reason":"DeviceTokenNotForTopic"}'), "INVALID_TOKEN");
  assert.equal(classifyApnsResponse(403, '{"reason":"InvalidProviderToken"}'), "FAILED");
  assert.equal(classifyApnsResponse(429, "not json"), "FAILED");
  // Timed out or never connected.
  assert.equal(classifyApnsResponse(0, ""), "FAILED");
});
