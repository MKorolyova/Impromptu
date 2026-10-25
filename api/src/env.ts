function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

function optionalEnv(name: string): string | null {
  return process.env[name] || null;
}

// Getters, so a script only needs the variables it actually uses.
export const env = {
  get DATABASE_URL() {
    return requireEnv("DATABASE_URL");
  },
  // Shared key callers send as `Authorization: Bearer <API_KEY>`. Optional: unset means no key is required.
  get API_KEY(): string | undefined {
    return process.env.API_KEY || undefined;
  },
  get GOOGLE_CLIENT_ID() {
    return requireEnv("GOOGLE_CLIENT_ID");
  },
  get GOOGLE_CLIENT_SECRET() {
    return requireEnv("GOOGLE_CLIENT_SECRET");
  },
  get GOOGLE_REDIRECT_URI() {
    return requireEnv("GOOGLE_REDIRECT_URI");
  },
  // 32 random bytes, base64. Encrypts stored refresh tokens.
  get TOKEN_ENCRYPTION_KEY() {
    return requireEnv("TOKEN_ENCRYPTION_KEY");
  },
  // Where the Google callback sends the user back to, e.g. the app's impromptu:// URL.
  get APP_REDIRECT_URL() {
    return requireEnv("APP_REDIRECT_URL");
  },
  // Classifies calendar events (stands in for Muse). Without it, a simple rule picks the activity.
  get GEMINI_API_KEY() {
    return optionalEnv("GEMINI_API_KEY");
  },
  get GEMINI_MODEL() {
    return optionalEnv("GEMINI_MODEL") ?? "gemini-3.5-flash-lite";
  },
  // Apple Push Notification service, for nearby alerts. Pushes are only sent when all four are set.
  // From an APNs auth key (Apple Developer > Keys): its Key ID, your Team ID, and the .p8 file's contents
  // (newlines may be written as \n).
  get APNS_KEY_ID() {
    return optionalEnv("APNS_KEY_ID");
  },
  get APNS_TEAM_ID() {
    return optionalEnv("APNS_TEAM_ID");
  },
  get APNS_PRIVATE_KEY() {
    return optionalEnv("APNS_PRIVATE_KEY");
  },
  // The iOS app's bundle ID, which APNs calls the topic.
  get APNS_BUNDLE_ID() {
    return optionalEnv("APNS_BUNDLE_ID");
  },
  // Space-separated, as Google expects in the `scope` parameter.
  get GOOGLE_CALENDAR_SCOPES() {
    return requireEnv("GOOGLE_CALENDAR_SCOPES").split(" ").filter(Boolean);
  },
};
