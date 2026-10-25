function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

// Getters, so a script only needs the variables it actually uses.
export const env = {
  get DATABASE_URL() {
    return requireEnv("DATABASE_URL");
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
  // Space-separated, as Google expects in the `scope` parameter.
  get GOOGLE_CALENDAR_SCOPES() {
    return requireEnv("GOOGLE_CALENDAR_SCOPES").split(" ").filter(Boolean);
  },
};
