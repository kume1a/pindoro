CREATE TABLE "account" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"username" text NOT NULL,
	"password_hash" text NOT NULL,
	"token_hash" text NOT NULL,
	"backup" "bytea",
	"backup_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "account_username_unique" UNIQUE("username"),
	CONSTRAINT "account_tokenHash_unique" UNIQUE("token_hash")
);
