CREATE TYPE "public"."push_environment" AS ENUM('SANDBOX', 'PRODUCTION');--> statement-breakpoint
CREATE TABLE "device_tokens" (
	"token" text PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"environment" "push_environment" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "nearby_alerts" (
	"recipient_id" uuid NOT NULL,
	"status_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "nearby_alerts_recipient_id_status_id_pk" PRIMARY KEY("recipient_id","status_id")
);
--> statement-breakpoint
ALTER TABLE "device_tokens" ADD CONSTRAINT "device_tokens_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "nearby_alerts" ADD CONSTRAINT "nearby_alerts_recipient_id_users_id_fk" FOREIGN KEY ("recipient_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "nearby_alerts" ADD CONSTRAINT "nearby_alerts_status_id_statuses_id_fk" FOREIGN KEY ("status_id") REFERENCES "public"."statuses"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "device_tokens_user_id_index" ON "device_tokens" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "nearby_alerts_status_id_index" ON "nearby_alerts" USING btree ("status_id");