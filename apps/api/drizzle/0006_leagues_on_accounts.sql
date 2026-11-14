-- Leagues move from anonymous players to accounts. Nothing links a player to an account, so the
-- old league rows go: a signed-in player rejoins with this week's XP on their next sync.
TRUNCATE "league_member", "league";--> statement-breakpoint
ALTER TABLE "league_member" DROP CONSTRAINT "league_member_player_id_player_id_fk";--> statement-breakpoint
ALTER TABLE "league_member" DROP CONSTRAINT "league_member_player_id_week_pk";--> statement-breakpoint
ALTER TABLE "league_member" DROP COLUMN "player_id";--> statement-breakpoint
DROP TABLE "player";--> statement-breakpoint
ALTER TABLE "league_member" ADD COLUMN "account_id" uuid NOT NULL;--> statement-breakpoint
ALTER TABLE "league_member" ADD CONSTRAINT "league_member_account_id_week_pk" PRIMARY KEY("account_id","week");--> statement-breakpoint
ALTER TABLE "league_member" ADD CONSTRAINT "league_member_account_id_account_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."account"("id") ON DELETE cascade ON UPDATE no action;
