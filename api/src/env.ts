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
  // Shared key callers send as `Authorization: Bearer <API_KEY>`.
  get API_KEY() {
    return requireEnv("API_KEY");
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
  // Space-separated, as Google expects in the `scope` parameter.
  get GOOGLE_CALENDAR_SCOPES() {
    return requireEnv("GOOGLE_CALENDAR_SCOPES").split(" ").filter(Boolean);
  },
};
