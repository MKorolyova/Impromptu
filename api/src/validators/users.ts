import { z } from "zod";
import { users } from "../db/schema.ts";
import { createInsertSchema, createSelectSchema, generatedColumns } from "./schema-factory.ts";

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
}).omit({ ...generatedColumns, deletedAt: true });

export type User = z.infer<typeof userSchema>;
export type CreateUserInput = z.infer<typeof createUserSchema>;
