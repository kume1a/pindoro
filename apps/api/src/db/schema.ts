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

const bytea = customType<{ data: Buffer }>({ dataType: () => "bytea" });

// A player's sign-in, progress backup (the app's SQLite file, gzipped) and league identity: the
// username is the name the league shows. The password is a salted scrypt hash; the token and the
// recovery code (null on accounts made before codes) are sha256 hashes.
export const account = pgTable("account", {
  id: uuid().primaryKey().defaultRandom(),
  username: text().notNull().unique(),
  passwordHash: text().notNull(),
  tokenHash: text().notNull().unique(),
  recoveryHash: text(),
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

// An account's place in one week's league: at most one league a week.
export const leagueMember = pgTable(
  "league_member",
  {
    accountId: uuid()
      .notNull()
      .references(() => account.id, { onDelete: "cascade" }),
    week: date({ mode: "string" }).notNull(),
    leagueId: uuid()
      .notNull()
      .references(() => league.id, { onDelete: "cascade" }),
    xp: integer().notNull(),
    joinedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.accountId, t.week] }), index().on(t.leagueId)],
);
