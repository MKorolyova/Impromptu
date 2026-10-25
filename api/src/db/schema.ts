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
    ...timestamps,
    ...softDelete,
  },
  (t) => [
    index().on(t.userId, t.expiresAt),
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