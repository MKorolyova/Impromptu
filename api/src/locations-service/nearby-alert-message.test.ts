import assert from "node:assert/strict";
import { test } from "node:test";
import { displayName, nearbyAlertText } from "./nearby-alert-message.ts";

test("tells someone who else started their activity", () => {
  assert.deepEqual(nearbyAlertText("Sam", "Grabbing coffee"), {
    title: "Sam is nearby",
    body: "Sam is also grabbing coffee within 3 miles.",
  });
});

test("names people the way the app does", () => {
  assert.equal(displayName({ firstName: "Jordan", nickname: "Jo" }), "Jo");
  assert.equal(displayName({ firstName: "Sam", nickname: null }), "Sam");
});
