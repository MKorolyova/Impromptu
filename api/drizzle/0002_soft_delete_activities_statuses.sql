DROP INDEX "users_email_unique";--> statement-breakpoint
ALTER TABLE "activities" ADD COLUMN "deleted_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "statuses" ADD COLUMN "deleted_at" timestamp with time zone;--> statement-breakpoint
CREATE UNIQUE INDEX "activities_custom_name_unique" ON "activities" USING btree ("owner_id",lower("name")) WHERE "activities"."owner_id" IS NOT NULL AND "activities"."deleted_at" IS NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "users_email_unique" ON "users" USING btree (lower("email")) WHERE "users"."deleted_at" IS NULL;