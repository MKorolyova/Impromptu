import { and, eq } from "drizzle-orm";
import { db } from "@/db/index";
import { calendarLinks } from "@/db/schema";
import type { GoogleChannel } from "@/types/google-channel";
import { decryptToken, encryptToken } from "@/utils/token-encryption";

const GOOGLE = "GOOGLE";

const isGoogleLinkFor = (userId: string) =>
  and(eq(calendarLinks.userId, userId), eq(calendarLinks.provider, GOOGLE));

// Every column except the refresh token, which is only read through getGoogleRefreshToken.
const linkColumns = {
  userId: calendarLinks.userId,
  provider: calendarLinks.provider,
  syncToken: calendarLinks.syncToken,
  channelId: calendarLinks.channelId,
  channelResourceId: calendarLinks.channelResourceId,
  channelToken: calendarLinks.channelToken,
  channelExpiresAt: calendarLinks.channelExpiresAt,
  createdAt: calendarLinks.createdAt,
  updatedAt: calendarLinks.updatedAt,
};

export type GoogleCalendarLink = Omit<typeof calendarLinks.$inferSelect, "encryptedRefreshToken">;

// Connecting again replaces the old token and clears sync state, so the next sync is a full one.
export async function saveGoogleCalendarLink(userId: string, refreshToken: string): Promise<void> {
  const encryptedRefreshToken = encryptToken(refreshToken);
  await db
    .insert(calendarLinks)
    .values({ userId, provider: GOOGLE, encryptedRefreshToken })
    .onConflictDoUpdate({
      target: [calendarLinks.userId, calendarLinks.provider],
      set: {
        encryptedRefreshToken,
        syncToken: null,
        channelId: null,
        channelResourceId: null,
        channelToken: null,
        channelExpiresAt: null,
      },
    });
}

export async function getGoogleCalendarLink(userId: string): Promise<GoogleCalendarLink | null> {
  const [link] = await db.select(linkColumns).from(calendarLinks).where(isGoogleLinkFor(userId)).limit(1);
  return link ?? null;
}

export async function getGoogleRefreshToken(userId: string): Promise<string | null> {
  const [link] = await db
    .select({ encryptedRefreshToken: calendarLinks.encryptedRefreshToken })
    .from(calendarLinks)
    .where(isGoogleLinkFor(userId))
    .limit(1);
  return link ? decryptToken(link.encryptedRefreshToken) : null;
}

export async function findGoogleCalendarLinkByChannelId(
  channelId: string,
): Promise<GoogleCalendarLink | null> {
  const [link] = await db
    .select(linkColumns)
    .from(calendarLinks)
    .where(eq(calendarLinks.channelId, channelId))
    .limit(1);
  return link ?? null;
}

// Pass null after Google answers 410, to force a full sync next time.
export async function updateGoogleSyncToken(userId: string, syncToken: string | null): Promise<void> {
  await db.update(calendarLinks).set({ syncToken }).where(isGoogleLinkFor(userId));
}

export async function updateGoogleChannel(userId: string, channel: GoogleChannel): Promise<void> {
  await db
    .update(calendarLinks)
    .set({
      channelId: channel.id,
      channelResourceId: channel.resourceId,
      channelToken: channel.token ?? null,
      channelExpiresAt: channel.expiration ? new Date(Number(channel.expiration)) : null,
    })
    .where(isGoogleLinkFor(userId));
}

export async function clearGoogleChannel(userId: string): Promise<void> {
  await db
    .update(calendarLinks)
    .set({ channelId: null, channelResourceId: null, channelToken: null, channelExpiresAt: null })
    .where(isGoogleLinkFor(userId));
}

export async function deleteGoogleCalendarLink(userId: string): Promise<void> {
  await db.delete(calendarLinks).where(isGoogleLinkFor(userId));
}
