CREATE TABLE "nearby_alerts" (
	"recipient_status_id" uuid NOT NULL,
	"other_user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "nearby_alerts_recipient_status_id_other_user_id_pk" PRIMARY KEY("recipient_status_id","other_user_id")
);
--> statement-breakpoint
ALTER TABLE "nearby_alerts" ADD CONSTRAINT "nearby_alerts_recipient_status_id_statuses_id_fk" FOREIGN KEY ("recipient_status_id") REFERENCES "public"."statuses"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "nearby_alerts" ADD CONSTRAINT "nearby_alerts_other_user_id_users_id_fk" FOREIGN KEY ("other_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "nearby_alerts_other_user_id_index" ON "nearby_alerts" USING btree ("other_user_id");