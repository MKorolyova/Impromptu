CREATE TABLE "oauth_states" (
	"state_hash" text PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "statuses" ADD COLUMN "google_event_id" text;--> statement-breakpoint
ALTER TABLE "oauth_states" ADD CONSTRAINT "oauth_states_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "statuses_google_event_unique" ON "statuses" USING btree ("user_id","google_event_id") WHERE "statuses"."google_event_id" IS NOT NULL AND "statuses"."deleted_at" IS NULL;