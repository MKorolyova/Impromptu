import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { env } from "../env.ts";
import * as schema from "./schema.ts";

// Reused across Next.js dev hot reloads, so each reload doesn't open a new pool.
// SSL comes from the URL (?sslmode=require for Tiger Cloud; none for the local Docker db).
const globalForDb = globalThis as typeof globalThis & { pgClient?: postgres.Sql };
const client = globalForDb.pgClient ?? postgres(env.DATABASE_URL, { ssl: "require", connect_timeout: 10 });
if (process.env.NODE_ENV !== "production") globalForDb.pgClient = client;

export const db = drizzle({ client, schema, casing: "snake_case" });

export type Database = typeof db;
export type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];

export function withTransaction<T>(fn: (tx: Transaction) => Promise<T>): Promise<T> {
  return db.transaction(fn);
}

export function closeDb(): Promise<void> {
  return client.end();
}
