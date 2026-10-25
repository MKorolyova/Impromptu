import assert from "node:assert/strict";
import { test } from "node:test";
import { displayName, nearbyAlertText } from "./nearby-alert-message.ts";

test("one person", () => {
  assert.deepEqual(nearbyAlertText(["Sam"], 1, "Grabbing coffee"), {
    title: "Sam is nearby",
    body: "Sam is also grabbing coffee within 3 miles.",
  });
});

test("two people", () => {
  assert.equal(nearbyAlertText(["Sam", "Jo"], 2, "Running").body, "Sam and Jo are also running within 3 miles.");
});

test("several new people, with others already announced", () => {
  assert.deepEqual(nearbyAlertText(["Sam", "Jo", "Priya"], 5, "Coding"), {
    title: "3 new people nearby",
    body: "Sam, Jo and 1 more are also coding within 3 miles. 5 people nearby in all.",
  });
});

test("nickname wins over the full name", () => {
  assert.equal(displayName({ firstName: "Jordan", lastName: "Park", nickname: "Jo" }), "Jo");
  assert.equal(displayName({ firstName: "Sam", lastName: "Lee", nickname: null }), "Sam Lee");
});
