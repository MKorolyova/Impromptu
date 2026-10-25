CREATE TABLE "user_locations" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"geom" geometry(point) NOT NULL,
	"accuracy_meters" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "user_locations" ADD CONSTRAINT "user_locations_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "user_locations_geom_index" ON "user_locations" USING gist ("geom");--> statement-breakpoint
CREATE INDEX "user_locations_updated_at_index" ON "user_locations" USING btree ("updated_at");