import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  geometry,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

const timestamptz = () => timestamp({ withTimezone: true });

const timestamps = {
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp({ withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
};

const softDelete = {
  deletedAt: timestamp({ withTimezone: true }),
};

export const TriggerType = pgEnum("trigger_type", ["CALENDAR", "PLACE", "INACTIVITY", "APP"]);
export const StatusSource = pgEnum("status_source", ["MANUAL","CALENDAR","LOCATION","AUTOMATED"]);
export const SharingResource = pgEnum("sharing_resource", ["LOCATION", "NOTES"]);
export const ShareLevel = pgEnum("share_level", ["NONE", "PLACE", "CITY", "EXACT"]);
export const CalendarProvider = pgEnum("calendar_provider", ["GOOGLE"]);
export const NoteRequestStatus = pgEnum("note_request_status", ["PENDING", "ANSWERED", "DECLINED"]);
// Which APNs server a device token belongs to: SANDBOX for builds run from Xcode, PRODUCTION otherwise.
export const PushEnvironment = pgEnum("push_environment", ["SANDBOX", "PRODUCTION"]);

export const users = pgTable("users", {
    id: uuid().primaryKey().defaultRandom(),
    email: text().notNull(),
    passwordHash: text().notNull(),
    firstName: text().notNull(),
    lastName: text().notNull(),
    nickname: text(),
    timezone: text().notNull(),
    ...timestamps,
    ...softDelete,
  },
  // Soft-deleted users free their email for a new account.
  (t) => [uniqueIndex("users_email_unique").on(sql`lower(${t.email})`).where(sql`${t.deletedAt} IS NULL`)],
);

export const friendships = pgTable("friendships", {
    userId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    friendId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    canSeeLocation: boolean().notNull().default(false),
    canSeeNotes: boolean().notNull().default(false),
    ...timestamps,
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.friendId] }),
    index().on(t.friendId),
    check("friendships_not_self", sql`${t.userId} <> ${t.friendId}`),
  ],
);

export const activities = pgTable("activities", {
    id: uuid().primaryKey().defaultRandom(),
    ownerId: uuid().references(() => users.id, { onDelete: "cascade" }),
    name: text().notNull(),
    iconId: uuid(),
    defaultDurationMinutes: integer().notNull(),
    // false = one of the standard activities from constants/activities.ts.
    isCustom: boolean().notNull().default(false),
    ...timestamps,
    ...softDelete,
  },
  (t) => [
    index().on(t.ownerId),
    uniqueIndex("activities_standard_name_unique").on(t.name).where(sql`${t.ownerId} IS NULL`),
    uniqueIndex("activities_custom_name_unique")
      .on(t.ownerId, sql`lower(${t.name})`)
      .where(sql`${t.ownerId} IS NOT NULL AND ${t.deletedAt} IS NULL`),
    check("activities_custom_has_owner", sql`${t.isCustom} = (${t.ownerId} IS NOT NULL)`),
    check("activities_duration_positive", sql`${t.defaultDurationMinutes} > 0`),
  ],
);

// The activities a user does often, picked at sign-up; the app's status drop-down lists these.
export const userActivities = pgTable("user_activities", {
    userId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    activityId: uuid().notNull().references(() => activities.id, { onDelete: "cascade" }),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.activityId] }),
    index().on(t.activityId),
  ],
);

export const activityTriggers = pgTable("activity_triggers", {
    id: uuid().primaryKey().defaultRandom(),
    activityId: uuid().notNull().references(() => activities.id, { onDelete: "cascade" }),
    type: TriggerType().notNull(),
    config: jsonb().$type<Record<string, unknown>>().notNull().default({}),
    enabled: boolean().notNull().default(true),
    ...timestamps,
  },
  (t) => [index().on(t.activityId)],
);

export const statuses = pgTable("statuses", {
    id: uuid().primaryKey().defaultRandom(),
    userId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    activityId: uuid().notNull().references(() => activities.id, { onDelete: "restrict" }),
    note: text(),
    source: StatusSource().notNull(),
    startedAt: timestamptz().notNull().defaultNow(),
    expiresAt: timestamptz().notNull(),
    // Set for CALENDAR statuses: the Google event (instance) this status was created from.
    googleEventId: text(),
    ...timestamps,
    ...softDelete,
  },
  (t) => [
    index().on(t.userId, t.expiresAt),
    uniqueIndex("statuses_google_event_unique")
      .on(t.userId, t.googleEventId)
      .where(sql`${t.googleEventId} IS NOT NULL AND ${t.deletedAt} IS NULL`),
    check("statuses_expires_after_start", sql`${t.expiresAt} > ${t.startedAt}`),
  ],
);

export const sharingRules = pgTable("sharing_rules", {
    id: uuid().primaryKey().defaultRandom(),
    ownerId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    subjectId: uuid().notNull(),
    resource: SharingResource().notNull(),
    level: ShareLevel().notNull().default("NONE"),
    expiresAt: timestamptz(),
    ...timestamps,
  },
  (t) => [
    index().on(t.ownerId, t.resource),
  ],
);

export const places = pgTable("places", {
    id: uuid().primaryKey().defaultRandom(),
    userId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    label: text().notNull(),
    geom: geometry({ type: "point", mode: "xy", srid: 4326 }).notNull(),
    radiusMeters: integer().notNull(),
    ...timestamps,
  },
  (t) => [
    index().on(t.userId),
    index().using("gist", t.geom),
    check("places_radius_positive", sql`${t.radiusMeters} > 0`),
  ],
);

// Each user's last reported position, for finding people nearby. Never returned to other users.
export const userLocations = pgTable("user_locations", {
    userId: uuid().primaryKey().references(() => users.id, { onDelete: "cascade" }),
    geom: geometry({ type: "point", mode: "xy", srid: 4326 }).notNull(),
    accuracyMeters: integer(),
    ...timestamps,
  },
  (t) => [
    index().using("gist", t.geom),
    index().on(t.updatedAt),
  ],
);

// APNs device tokens, for push notifications. A device belongs to whoever signed in on it last.
export const deviceTokens = pgTable("device_tokens", {
    token: text().primaryKey(),
    userId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    environment: PushEnvironment().notNull(),
    ...timestamps,
  },
  (t) => [index().on(t.userId)],
);

// Nearby push alerts already accounted for: during the recipient's status, they've been told about this
// other person, or the person was already nearby when the status began (so it's no news). Each person is
// announced at most once per status of the recipient.
export const nearbyAlerts = pgTable("nearby_alerts", {
    recipientStatusId: uuid().notNull().references(() => statuses.id, { onDelete: "cascade" }),
    otherUserId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.recipientStatusId, t.otherUserId] }), index().on(t.otherUserId)],
);

// One user asking someone nearby for a note; answered with text, and optionally a place and a position.
export const noteRequests = pgTable("note_requests", {
    id: uuid().primaryKey().defaultRandom(),
    requesterId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    recipientId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    // The activity they were both doing when it was sent.
    activityId: uuid().references(() => activities.id, { onDelete: "set null" }),
    status: NoteRequestStatus().notNull().default("PENDING"),
    replyText: text(),
    replyPlaceLabel: text(),
    replyGeom: geometry({ type: "point", mode: "xy", srid: 4326 }),
    respondedAt: timestamptz(),
    // A pending request can't be answered after this.
    expiresAt: timestamptz().notNull(),
    ...timestamps,
  },
  (t) => [
    index().on(t.recipientId, t.createdAt),
    index().on(t.requesterId, t.createdAt),
    check("note_requests_not_self", sql`${t.requesterId} <> ${t.recipientId}`),
    check("note_requests_answered_has_text", sql`${t.status} <> 'ANSWERED' OR ${t.replyText} IS NOT NULL`),
  ],
);

export const calendarLinks = pgTable("calendar_links", {
    userId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    provider: CalendarProvider().notNull(),
    encryptedRefreshToken: text().notNull(),
    syncToken: text(),
    // Google push channel; resourceId is needed to stop it, token verifies its notifications.
    channelId: text(),
    channelResourceId: text(),
    channelToken: text(),
    channelExpiresAt: timestamptz(),
    ...timestamps,
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.provider] }),
    uniqueIndex("calendar_links_channel_id_unique").on(t.channelId),
  ],
);

// One-time OAuth `state` values, so the Google callback knows which user started connecting.
export const oauthStates = pgTable("oauth_states", {
  // SHA-256 of the state; the raw value only travels through Google's redirect.
  stateHash: text().primaryKey(),
  userId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
  expiresAt: timestamptz().notNull(),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

export const conversations = pgTable("conversations", {
    id: uuid().primaryKey().defaultRandom(),
    userAId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    userBId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    ...timestamps,
  },
  (t) => [
    uniqueIndex("conversations_pair_unique").on(t.userAId, t.userBId),
    index().on(t.userBId),
    check("conversations_ordered_pair", sql`${t.userAId} < ${t.userBId}`),
  ],
);

export const messages = pgTable("messages", {
    id: uuid().primaryKey().defaultRandom(),
    conversationId: uuid().notNull().references(() => conversations.id, { onDelete: "cascade" }),
    senderId: uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
    body: text().notNull(),
    // Set when the other person reads the message.
    readAt: timestamptz(),
    ...timestamps,
  },
  (t) => [index().on(t.conversationId, t.createdAt)],
);