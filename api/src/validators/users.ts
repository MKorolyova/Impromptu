import { z } from "zod";
import { users } from "@/db/schema";
import { createInsertSchema, createSelectSchema, softDeletableColumns } from "@/validators/schema-factory";

const isTimezone = (value: string) => {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value });
    return true;
  } catch {
    return false;
  }
};

export const userSchema = createSelectSchema(users);

export const createUserSchema = createInsertSchema(users, {
  email: () => z.string().trim().toLowerCase().pipe(z.email()),
  passwordHash: (s) => s.min(1),
  firstName: (s) => s.trim().min(1).max(100),
  lastName: (s) => s.trim().min(1).max(100),
  nickname: (s) => s.trim().min(1).max(50),
  timezone: (s) => s.refine(isTimezone, "Invalid IANA timezone"),
}).omit(softDeletableColumns);

// Body of POST /api/v1/users. The password is hashed before it reaches createUserSchema.
export const createUserRequestSchema = createUserSchema
  .omit({ passwordHash: true })
  .extend({ password: z.string().min(8, "Password must be at least 8 characters").max(128) });

// Body of POST /api/v1/users/search. The email goes in the body, never the URL.
export const searchUsersRequestSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email()),
});

// Query of GET /api/v1/users. `cursor` is the `nextCursor` from the previous page.
export const listUsersQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  cursor: z.string().optional(),
});

// Body of POST /api/v1/auth/login.
export const loginRequestSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email()),
  password: z.string().min(1).max(128),
});

export type User = z.infer<typeof userSchema>;
export type CreateUserInput = z.infer<typeof createUserSchema>;
export type CreateUserRequest = z.infer<typeof createUserRequestSchema>;
export type LoginRequest = z.infer<typeof loginRequestSchema>;
