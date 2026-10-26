import assert from "node:assert/strict";
import { test } from "node:test";
import type { GoogleCalendarListEntry } from "../types/google-calendar.ts";
import { ownCalendarIds } from "./google-calendar.ts";

const calendar = (id: string, fields: Partial<GoogleCalendarListEntry>): GoogleCalendarListEntry => ({
  kind: "calendar#calendarListEntry",
  etag: id,
  id,
  summary: id,
  accessRole: "owner",
  ...fields,
});

test("reads your own calendars, not ones shared with you", () => {
  const ids = ownCalendarIds([
    calendar("ada@example.com", { primary: true, selected: true }),
    calendar("classes", { selected: true }),
    calendar("hidden-project", { selected: false }),
    calendar("team-shared", { accessRole: "writer", selected: true }),
    calendar("holidays", { accessRole: "reader", selected: true }),
    calendar("old", { selected: true, deleted: true }),
  ]);
  assert.deepEqual(ids, ["ada@example.com", "classes"]);
});

test("the primary calendar counts even when Google omits selected", () => {
  assert.deepEqual(ownCalendarIds([calendar("ada@example.com", { primary: true })]), ["ada@example.com"]);
});
