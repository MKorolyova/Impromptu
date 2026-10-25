import type { NextApiRequest, NextApiResponse } from "next";

export type ApiErrorCode =
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "VALIDATION_FAILED"
  | "CONFLICT"
  | "RATE_LIMITED"
  | "INTERNAL";

const STATUS_BY_CODE: Record<ApiErrorCode, number> = {
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  VALIDATION_FAILED: 400,
  CONFLICT: 409,
  RATE_LIMITED: 429,
  INTERNAL: 500,
};

export type ApiError = { error: { code: ApiErrorCode; message: string } };

export function sendError(res: NextApiResponse, code: ApiErrorCode, message: string): void {
  res.status(STATUS_BY_CODE[code]).json({ error: { code, message } } satisfies ApiError);
}

export function rejectMethod(res: NextApiResponse, allowed: string[]): void {
  res.setHeader("Allow", allowed.join(", "));
  res.status(405).json({ error: { code: "VALIDATION_FAILED", message: "Method not allowed" } });
}

// Routes for local testing only; they take a userId directly because there is no auth yet.
export function blockOutsideDevelopment(res: NextApiResponse): boolean {
  if (process.env.NODE_ENV === "production") {
    sendError(res, "NOT_FOUND", "Not found");
    return true;
  }
  return false;
}

const CONNECTION_ERROR_CODES = new Set(["CONNECT_TIMEOUT", "ECONNREFUSED", "ENOTFOUND", "ETIMEDOUT"]);

// Drizzle wraps driver errors, so look at the cause too.
export function isDatabaseUnreachable(error: unknown): boolean {
  for (let e = error; e instanceof Error; e = e.cause) {
    if (CONNECTION_ERROR_CODES.has((e as { code?: string }).code ?? "")) return true;
  }
  return false;
}

export const DATABASE_UNREACHABLE_MESSAGE =
  "Can't reach the database. Check that DATABASE_URL is right and that this machine can connect to it.";

type ApiHandler = (req: NextApiRequest, res: NextApiResponse) => unknown;

// Turns unexpected errors into the standard error shape instead of a bare 500.
export function withApiErrors(handler: ApiHandler): ApiHandler {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (error) {
      if (res.headersSent) throw error;
      if (isDatabaseUnreachable(error)) return sendError(res, "INTERNAL", DATABASE_UNREACHABLE_MESSAGE);
      console.error(error);
      sendError(res, "INTERNAL", "Something went wrong");
    }
  };
}
