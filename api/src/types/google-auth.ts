// Google OAuth 2.0 token shapes.
export type GoogleTokenResponse = {
  access_token: string;
  expires_in: number;
  // Only returned on the first consent, or when prompt=consent is used.
  refresh_token?: string;
  scope: string;
  token_type: "Bearer";
  id_token?: string;
};

export type GoogleTokens = {
  accessToken: string;
  accessTokenExpiresAt: Date;
  refreshToken: string | null;
  scopes: string[];
};
