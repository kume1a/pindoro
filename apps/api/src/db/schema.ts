import {
  customType,
  date,
  index,
  integer,
  pgTable,
  primaryKey,
  smallint,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";

// An anonymous league player: the app holds the token, the server only its sha256.
export const player = pgTable("player", {
  id: uuid().primaryKey().defaultRandom(),
  tokenHash: text().notNull().unique(),
  name: text().notNull(),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

const bytea = customType<{ data: Buffer }>({ dataType: () => "bytea" });

// A signed-in player's progress backup: the app's SQLite file, gzipped. Not a league player, so
// leaving Leagues never touches it. The password is a salted scrypt hash, the token a sha256.
export const account = pgTable("account", {
  id: uuid().primaryKey().defaultRandom(),
  username: text().notNull().unique(),
  passwordHash: text().notNull(),
  tokenHash: text().notNull().unique(),
  backup: bytea(),
  backupAt: timestamp({ withTimezone: true }),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

// One league of up to 30 players for a week (its Monday in Tbilisi) and tier (0 Alley … 5 Highway).
export const league = pgTable(
  "league",
  {
    id: uuid().primaryKey().defaultRandom(),
    week: date({ mode: "string" }).notNull(),
    tier: smallint().notNull(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index().on(t.week, t.tier)],
);

// A player's place in one week's league: at most one league a week.
export const leagueMember = pgTable(
  "league_member",
  {
    playerId: uuid()
      .notNull()
      .references(() => player.id, { onDelete: "cascade" }),
    week: date({ mode: "string" }).notNull(),
    leagueId: uuid()
      .notNull()
      .references(() => league.id, { onDelete: "cascade" }),
    xp: integer().notNull(),
    joinedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.playerId, t.week] }), index().on(t.leagueId)],
);
