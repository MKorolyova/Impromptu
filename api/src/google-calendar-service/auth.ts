import { env } from "../env.ts";
import { googleRequest } from "./google-request.ts";
import type { GoogleTokenResponse, GoogleTokens } from "../types/google-auth.ts";

const AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const REVOKE_URL = "https://oauth2.googleapis.com/revoke";

function toGoogleTokens(response: GoogleTokenResponse): GoogleTokens {
  return {
    accessToken: response.access_token,
    accessTokenExpiresAt: new Date(Date.now() + response.expires_in * 1000),
    refreshToken: response.refresh_token ?? null,
    scopes: response.scope.split(" "),
  };
}

function postForm<T>(url: string, params: Record<string, string>): Promise<T> {
  return googleRequest<T>(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
}

// `state` must be random per request and checked in the callback to prevent CSRF.
export function buildGoogleAuthUrl(state: string): string {
  const url = new URL(AUTH_URL);
  url.search = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    redirect_uri: env.GOOGLE_REDIRECT_URI,
    response_type: "code",
    scope: env.GOOGLE_CALENDAR_SCOPES.join(" "),
    // offline + consent makes Google return a refresh token.
    access_type: "offline",
    prompt: "consent",
    include_granted_scopes: "true",
    state,
  }).toString();
  return url.toString();
}

export async function exchangeGoogleAuthCode(code: string): Promise<GoogleTokens> {
  const response = await postForm<GoogleTokenResponse>(TOKEN_URL, {
    code,
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    redirect_uri: env.GOOGLE_REDIRECT_URI,
    grant_type: "authorization_code",
  });
  return toGoogleTokens(response);
}

export async function refreshGoogleAccessToken(refreshToken: string): Promise<GoogleTokens> {
  const response = await postForm<GoogleTokenResponse>(TOKEN_URL, {
    refresh_token: refreshToken,
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    grant_type: "refresh_token",
  });
  return toGoogleTokens(response);
}

export async function revokeGoogleToken(token: string): Promise<void> {
  await postForm<void>(REVOKE_URL, { token });
}
