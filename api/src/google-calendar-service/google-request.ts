import type { GoogleErrorBody } from "../types/google-error.ts";

const REQUEST_TIMEOUT_MS = 10_000;

export class GoogleApiError extends Error {
  readonly status: number;
  readonly reason: string;

  constructor(status: number, reason: string, message: string) {
    super(message);
    this.name = "GoogleApiError";
    this.status = status;
    this.reason = reason;
  }

  // The refresh token was revoked or expired; the user has to connect Google again.
  get isInvalidGrant(): boolean {
    return this.reason === "invalid_grant";
  }

  // A sync token is no longer valid; do a full sync instead.
  get isSyncTokenExpired(): boolean {
    return this.status === 410;
  }
}

async function toGoogleApiError(response: Response): Promise<GoogleApiError> {
  const body = (await response.json().catch(() => null)) as GoogleErrorBody | null;
  const error = body?.error;
  if (typeof error === "string") {
    return new GoogleApiError(response.status, error, body?.error_description ?? error);
  }
  return new GoogleApiError(
    response.status,
    error?.errors?.[0]?.reason ?? error?.status ?? "unknown",
    error?.message ?? `Google request failed with status ${response.status}`,
  );
}

export async function googleRequest<T>(url: URL | string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
  if (!response.ok) {
    throw await toGoogleApiError(response);
  }
  if (response.status === 204 || response.headers.get("content-length") === "0") {
    return undefined as T;
  }
  return (await response.json()) as T;
}
