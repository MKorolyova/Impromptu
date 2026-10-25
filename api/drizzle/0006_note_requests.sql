CREATE TYPE "public"."note_request_status" AS ENUM('PENDING', 'ANSWERED', 'DECLINED');--> statement-breakpoint
CREATE TABLE "note_requests" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"requester_id" uuid NOT NULL,
	"recipient_id" uuid NOT NULL,
	"activity_id" uuid,
	"status" "note_request_status" DEFAULT 'PENDING' NOT NULL,
	"reply_text" text,
	"reply_place_label" text,
	"reply_geom" geometry(point, 4326),
	"responded_at" timestamp with time zone,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "note_requests_not_self" CHECK ("note_requests"."requester_id" <> "note_requests"."recipient_id"),
	CONSTRAINT "note_requests_answered_has_text" CHECK ("note_requests"."status" <> 'ANSWERED' OR "note_requests"."reply_text" IS NOT NULL)
);
--> statement-breakpoint
ALTER TABLE "note_requests" ADD CONSTRAINT "note_requests_requester_id_users_id_fk" FOREIGN KEY ("requester_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "note_requests" ADD CONSTRAINT "note_requests_recipient_id_users_id_fk" FOREIGN KEY ("recipient_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "note_requests" ADD CONSTRAINT "note_requests_activity_id_activities_id_fk" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "note_requests_recipient_id_created_at_index" ON "note_requests" USING btree ("recipient_id","created_at");--> statement-breakpoint
CREATE INDEX "note_requests_requester_id_created_at_index" ON "note_requests" USING btree ("requester_id","created_at");